# SMS Collection Feature

Location: `lib/features/sms_inbox/`

Android-only feature that scans the device's SMS inbox for bank/transaction messages, parses them into structured transaction data, and lets the user review and convert them into real app records (transactions, bills, obligations). Runs entirely on-device — nothing SMS-related is stored in Firestore.

## 1. Collection (reading SMS + notification captures)

- **Package**: `flutter_sms_inbox` (reads the Android SMS content provider; returns nothing on non-Android platforms) + `permission_handler` for the `SMS` runtime permission.
- `data/sms_reader_adapter.dart` — wraps `SmsQuery().querySms()`, pulls the latest 500 inbox messages.
- `data/sms_permission_service.dart` — wraps `Permission.sms`, exposes an `SmsAvailability` enum (`granted` / `denied` / `permanentlyDenied` / `notRequestedYet` / `unsupportedPlatform`), and remembers whether the user has already been asked (via `LocalSettingsService`).
- **Notification capture (supplementary source)**: `content://sms` never contains RCS messages (e.g. RCS Business Messaging bank alerts through Google Messages) — there is no public Android API that exposes RCS content to a third-party app. `android/app/src/main/kotlin/.../NotificationCaptureListenerService.kt` is a `NotificationListenerService` that captures notification text from the device's current default SMS/RCS app only, pre-filters for financial-looking content, and stores matches in its own small SQLite file (`NotificationCaptureStore.kt`). `data/notification_capture_adapter.dart` pulls those rows via the `finance_app/notification_listener` method channel (`MainActivity.kt`), mapped into the same `RawSmsMessage` shape as device SMS (tagged `SmsMessageSource.notification`). `data/notification_access_service.dart` mirrors `sms_permission_service.dart`'s pattern for the separate, OS-level "notification access" toggle (no in-app dialog — `NotificationAccessAvailability` gates a dismissible banner, not a hard block, since device-SMS reading works fine without it). Only ever sees notifications posted *after* being enabled — no historical backfill is possible. Removed entirely from the `play` flavor build (`src/play/AndroidManifest.xml`), same Play-policy rationale as `READ_SMS`.
- **Trigger model**: manual only for scanning. `SmsInboxItemsNotifier.scan()` (`presentation/providers/sms_inbox_providers.dart`) is invoked when the user opens/refreshes the SMS Inbox screen, and reads both sources. The notification listener service itself *does* run continuously in the background once enabled (that's what lets it observe notifications as they arrive — there is no way to query past notifications), but it only ever writes to its own local capture store; nothing is scanned/parsed/persisted into `sms_inbox` until the next manual scan, and it is never triggered implicitly from Dashboard or History loads.

## 2. Filtering

- `domain/sms_parser.dart` → `SmsFinancialFilter.isFinancial()`:
  1. Hard-reject regexes for OTP/verification/"don't share your PIN/CVV" messages.
  2. Transaction-verb signals (debited, credited, spent, paid, UPI, IMPS, NEFT, RTGS, EMI) short-circuit to accept.
  3. Soft-reject regexes for promotions/recharge offers/delivery updates/sale text.
  4. Fallback: accept if amount + account/card-number pattern is present.
- `domain/bank_sender_matcher.dart` → `BankSenderMatcher`: normalizes DLT sender IDs (strips the 2-letter carrier route prefix, e.g. `VM-HDFCBK` → `HDFCBK`) and maps the header to a known bank name/logo (HDFC, ICICI, SBI, Axis, etc.). This is used for **display/matching**, not as a hard whitelist — unrecognized senders can still pass the financial filter.
- `domain/filter/` (`sms_filter_criteria.dart`, `sms_card_matcher.dart`, `sms_date_range_filter.dart`, `sms_sort_order.dart`) — secondary, in-memory UI filters applied *after* parsing (by bank, card, category, date range, duplicate status).

## 3. Parsing

- `domain/sms_parser.dart` — abstract `SmsParser` base (`canParse` / `parse`).
- `domain/sms_parser_registry.dart` — `SmsParserRegistry` tries parsers in order: HDFC → ICICI → SBI → Axis → generic UPI → generic fallback. First match wins.
- Bank-specific parsers: `domain/bank_parsers/hdfc_sms_parser.dart`, `icici_sms_parser.dart`, `sbi_sms_parser.dart`, `axis_sms_parser.dart`, plus `generic_upi_sms_parser.dart` and `generic_fallback_sms_parser.dart`.
- `domain/sms_regex_utils.dart` — shared regex helpers for amount, account/card last-4, and reference number extraction.
- Output model: `domain/parsed_sms_transaction.dart` (amount, direction, merchant/sender, bank name, reference number, category), with supporting enums `sms_transaction_direction.dart` and `sms_transaction_category.dart`.

## 4. From parsed SMS to real transactions

- `domain/sms_inbox_item.dart` — wraps the raw SMS + parsed data + review status.
- `data/sms_inbox_database.dart` + `sms_inbox_dao.dart` — **local sqflite storage only**; deliberately not synced to Firestore (per in-code design comment). `firestore_constants.dart` has no SMS-specific collection, confirming this.
- `data/sms_inbox_repository.dart` — orchestrates scan → parse → dedup → persist to sqflite.
- `presentation/sms_conversion_router.dart` + `sms_bulk_converter.dart` — once the user confirms an item, routes it into the real Firestore-backed repositories (`TransactionRepository`, `ExpenseRepository`, etc.).
- `domain/sms_conversion_target.dart`, `sms_prefill.dart` — map parsed SMS fields into the prefill form for the chosen target record type.

## 5. Duplicate detection

- `domain/sms_dedup_key.dart` — `SmsDedupKey.compute()`: SHA-256 hash of normalized sender + timestamp + amount + (reference number or body). Exact-match only — this is what device-SMS-vs-device-SMS comparisons use, since they share one clock.
- `domain/sms_message_key.dart` — a separate identity key (sender + time + body) used for delete-tombstoning, distinct from the dedup key.
- `data/sms_inbox_dao.dart::findLikelyOriginalByFuzzyMatch()` — a looser, time-windowed (±5 min) same-sender/amount check used *only* for a notification-sourced item, since its postTime isn't the same clock as the device SMS provider's `date` column and would never match `SmsDedupKey`'s exact hash. Prevents a bank that sends both a real SMS and a notification for the same transaction from being double-counted; never runs for device-SMS-vs-device-SMS comparisons.
- `duplicateOfId` / `duplicateReason` are set in `sms_inbox_repository.dart::scanInbox()`; reasons enumerated in `domain/sms_duplicate_reason.dart` (`sameReferenceNumber` vs `sameSenderAmountAndTime`).
- UI: `presentation/widgets/sms_duplicate_review_sheet.dart`, with providers `smsDuplicateOriginalProvider` / `smsDuplicateCountProvider`.

> Note: there is a known gap where deleting a non-duplicate SMS can orphan `duplicate_of_id` references on other items — deferred for a future Duplicate Management redesign rather than a standalone patch.

## 6. UI

- `presentation/screens/sms_inbox_screen.dart` — main inbox/review list.
- `presentation/widgets/`:
  - `sms_permission_gate_view.dart` — grant/settings flow when SMS permission isn't yet granted (blocks the whole inbox).
  - `notification_capture_banner.dart` — dismissible, non-blocking banner prompting for notification access when it isn't granted.
  - `sms_filter_sheet.dart`, `sms_active_filter_chips.dart` — filtering UI.
  - `sms_convert_sheet.dart`, `sms_bulk_convert_sheet.dart` — convert one/many SMS into transactions, bills, or obligations.
  - `sms_bill_picker_sheet.dart`, `sms_obligation_picker_sheet.dart` — target-record pickers.
  - `sms_duplicate_review_sheet.dart` — review/resolve duplicates.
  - `sms_message_detail_sheet.dart`, `sms_multi_select_toolbar.dart`, `sms_empty_state.dart`, `sms_inbox_skeleton_list.dart`.
- Entry points: `lib/core/router/app_router.dart` and a pending-count badge/link in `lib/features/transactions/presentation/screens/transactions_screen.dart`.

## 7. Trigger summary

No periodic scan exists, and scanning into `sms_inbox` is strictly manual/on-demand (latest 500 device-SMS messages plus whatever the notification listener has captured since last enabled), deduped against local sqflite state on every run. The notification listener service itself does run continuously once the user enables it (there is no way to query past notifications otherwise), but it only ever writes to its own separate local capture store — nothing reaches `sms_inbox`, gets parsed, or is scanned/persisted until the next manual scan runs.
