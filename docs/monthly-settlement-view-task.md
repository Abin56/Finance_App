# Task: Monthly Settlement View (custom billing-cycle spending view)

**For:** a future Claude implementation session.
**Prereq:** read this whole file before writing code. Then draft a short plan
(EnterPlanMode), confirm the one scope decision in §5 with the user, and implement.

---

## 1. What the user wants (in their words)

> Remember/customize the settlement month. Example: my credit-card bill is
> generated every **17th** of the month and I pay it on the **5th of the next
> month**. Show **this settlement month's total expense amount**, and don't
> forget the **previous month's pending amount** as extra detail. Add a
> feature: a **"Monthly Settlement View"** that organizes spending by this
> custom cycle instead of the calendar month.

Plain-language restatement of the feature:

- People's real money runs on a **statement cycle**, not the 1st-to-31st
  calendar month. A "settlement month" is `[statement day of month N] →
  [day before statement day of month N+1]`, with payment due on a configurable
  day of a later month (e.g. the 5th).
- The user wants a screen/section that, for the **current cycle**, shows:
  1. **This settlement month's total spending** (running total of the
     in-progress cycle).
  2. **Last cycle's still-unpaid (pending) amount**, carried forward as an
     explicit line — so they see "you still owe ₹X from last month" on top of
     "you've spent ₹Y this month."
- Spending is grouped **by settlement cycle**, newest first.

---

## 2. Critical: most of this already exists — REUSE, don't rebuild

Before writing anything new, understand what the codebase already has. The
credit-cards feature already models exactly the "17th / pay 5th next month"
cycle. **Do not reimplement cycle math, statement totals, or due-date
clamping** — reuse these:

| Existing piece | File | What it gives you |
|---|---|---|
| `CreditCardProfile` | `lib/features/credit_cards/domain/credit_card_profile.dart` | Per-card `statementDay` (e.g. 17) + `paymentDueDay` (e.g. 5, "day of the month *after* close"). 1:1 with an `Account`. This IS the user's cycle config. |
| `StatementPeriod` + `StatementPeriodCalculator` | `lib/features/credit_cards/domain/statement_period.dart` | Pure functions: `currentCycleFor(card, {now})` → the in-progress (not-yet-closed) cycle window + `dueDate`; `mostRecentClosedCycleFor(card, {now})`; month-clamping for short months. `StatementPeriod.contains(date)`. |
| `Statement` | `lib/features/credit_cards/domain/statement.dart` | A **closed** cycle materialized with `totalAmount`, `amountPaid`, `remainingAmount`, `dueDate`, `status` (pending/dueSoon/overdue/partiallyPaid/paid), `contains(date)`. `remainingAmount` of the previous statement = the "previous month pending" the user asked for. |
| `StatementRepository.materializeIfDue` | `lib/features/credit_cards/data/statement_repository.dart` | Closes a cycle into a `Statement` once its `periodEnd` has passed. |
| `transactionsForCardProvider(cardId)` | `lib/features/credit_cards/presentation/providers/credit_card_providers.dart` | All (non-deleted) transactions on a card account. |
| `creditCardSpendForRangeProvider({start,end})` | `lib/features/credit_cards/presentation/providers/credit_card_report_providers.dart` | Sum of card-account transactions in a date range. |
| `statementsStreamProvider(cardId)` | `lib/features/credit_cards/presentation/providers/credit_card_providers.dart` | A card's materialized statements. |
| `personStatementGroupsProvider(personId)` | `lib/features/people/presentation/providers/person_statement_grouping_providers.dart` | Precedent for "group expense shares by statement period" — the Contact Ledger's Summary tab already uses it. |
| `StatementDetailScreen` / `CreditCardDetailScreen` | `lib/features/credit_cards/presentation/screens/` | Existing per-statement and per-card UI to mirror in style. |

**Key nuance:** the **current** (in-progress) cycle is NOT a `Statement` yet —
statements only materialize once closed. So "this settlement month's total"
must be computed **live**: `StatementPeriodCalculator.currentCycleFor(card)`
gives the window, then sum `transactionsForCardProvider(card.id)` where
`period.contains(t.dateTime)`. The **previous** month's pending comes from the
most recent closed `Statement.remainingAmount`.

Reuse conventions the codebase already follows:
- Live status via computed getters, `overdue = dueDate < today && unpaid`
  (see `Statement.status` / `Installment.status`) — never a stored "overdue".
- Money-direction pill: `lib/shared/widgets/states/money_direction_indicator.dart`.
- Expense status pill: `lib/shared/widgets/states/expense_status_pill.dart`.
- `AppCard`, `AppSizes`, `context.colors`, `context.textTheme`,
  `CurrencyFormatter.instance.format`, `DateTimeX` (`fullDate`, `monthYear`).

---

## 3. Feature requirements (the "what")

Build a **Settlement View** that, per settlement cycle, shows:

1. **Cycle header** — the settlement month labelled in plain language
   (e.g. "17 Jun – 16 Jul", "Due 5 Aug"), NOT "statement period".
2. **This cycle's total spending** — live running total for the current cycle;
   the materialized `totalAmount` for closed cycles.
3. **Previous cycle's pending carryover** — an explicit line: the most recent
   closed cycle's `remainingAmount` (what's still unpaid from before), shown
   above/beside this cycle's spending so the user sees both at once.
4. **Amount due & due date** — for a closed cycle: `remainingAmount` + `dueDate`
   + status pill (Due soon / Overdue / Paid…). For the current in-progress
   cycle: projected due date (`currentCycleFor(card).dueDate`).
5. **Cycle breakdown list** — the transactions/expenses inside the cycle,
   newest first, tappable through to their detail
   (`/transactions/{id}` or the People `PersonExpenseDetailScreen`).
6. **Cycle switcher** — navigate to previous/next cycles (or a list of closed
   `Statement`s) so the user can review history month by month.

---

## 4. Where it lives / entry points

Pick during planning, but the natural homes are:

- **Primary:** a new **Settlement View** section on `CreditCardDetailScreen`
  (or a dedicated `SettlementCycleScreen` reachable from it) — this is the most
  faithful to "my credit card bill." Each card already has its cycle config.
- **Secondary (optional, gated by §5 decision):** a global **"Financial
  month"** toggle on the Dashboard / Reports that reorganizes the whole
  spending summary by a user-chosen cycle even for non-card accounts.

Do NOT duplicate cycle math between these — both consume the same
`StatementPeriodCalculator` + a new provider layer (see §6).

---

## 5. ⚠️ One scope decision to confirm with the user before coding

Ask via `AskUserQuestion`:

**"Should the custom settlement cycle be per credit card (each card keeps its
own 17th/5th cycle — already supported), or also a single global 'financial
month' that regroups ALL spending (including cash/bank accounts)?"**

- **Option A (recommended, smaller):** Per-card only. Reuse `CreditCardProfile`
  as-is; build the Settlement View on the card detail screen. No new stored
  config, no new settings surface. Fastest, and matches the "credit card bill"
  framing exactly.
- **Option B (larger):** Add a global default cycle (a `statementDay` +
  `paymentDueDay` stored via `LocalSettingsService.setInt` — see
  `lib/core/services/local_settings_service.dart`, `getInt`/`setInt`) plus a
  Settings screen field, and a Dashboard/Reports "by financial month" view that
  buckets every account's transactions into that global cycle. More surface
  area, more edge cases (multiple cards with different cycles vs one global
  cycle).

Everything below is written for **Option A** and notes where Option B differs.

---

## 6. Proposed implementation (Option A)

### 6.1 Domain (mostly reuse)
- No new cycle math. If any helper is missing, add a pure function to
  `StatementPeriodCalculator`, e.g. `previousClosedCycleFor(card, {now})` and
  `cycleContaining(card, date, {now})` — keep them pure + unit-tested, matching
  the existing style in `statement_period.dart`.

### 6.2 Providers (new — thin, reuse the pieces in §2)
Create `lib/features/credit_cards/presentation/providers/settlement_view_providers.dart`:

- `currentCycleSpendProvider(cardId)` → `({StatementPeriod period, double total})`:
  `currentCycleFor(card)` window summed over `transactionsForCardProvider(cardId)`
  via `period.contains(t.dateTime)`. This is the live "this settlement month's
  total."
- `previousCyclePendingProvider(cardId)` → `double`: the most recent closed
  `Statement.remainingAmount` (0 if none / fully paid). This is the "previous
  month pending amount detail."
- `settlementCyclesProvider(cardId)` → an ordered list combining the live
  current cycle (as a synthetic, not-yet-`Statement` entry) with the
  materialized closed `Statement`s, newest first — the data for the cycle
  switcher / history list.

Keep these as `Provider.family` over `cardId`, consistent with the existing
credit-card providers. No repository writes here — this is read/derive only.

### 6.3 UI (new)
- `SettlementSummaryCard` widget: two headline numbers side by side —
  **"Spent this month"** (`currentCycleSpendProvider.total`) and **"Still to
  pay from last month"** (`previousCyclePendingProvider`) — plus the cycle
  label and due date. Follow `PersonExpenseStatsCard`'s two-column layout as a
  style reference (`lib/features/people/presentation/widgets/person_expense_stats_card.dart`).
- Cycle breakdown list: reuse the History-tile card style from
  `person_statement_screen.dart`'s `_ContactLedgerTile` or `HistoryTile`.
- Cycle switcher: prev/next chevrons on the summary card, or a horizontally
  scrollable month chip row.
- Add the Settlement View either inline on `CreditCardDetailScreen` or as a new
  screen pushed from it (add a route in `lib/core/router/app_routes.dart` +
  `app_router.dart` following the `statementDetail` pattern if it's its own
  screen).

### 6.4 Plain-language copy (REQUIRED — see project memory rule)
The UI must avoid accounting jargon (project rule: *never use accounting jargon
in the UI; internal code can keep proper terms*). Use e.g.:
- "This month's spending" — not "current statement liability"
- "Still to pay from last month" — not "prior period outstanding"
- "Due 5 Aug" — not "payment due date of billing cycle"
- "17 Jun – 16 Jul" — a plain date range, not "statement period"

---

## 7. Edge cases to handle
- **No statement generated yet** (new card, first cycle not closed): current
  cycle total shows live; previous-cycle pending shows ₹0 / "nothing carried
  over."
- **Short months / day 31**: already handled by `StatementPeriodCalculator`'s
  clamping — reuse it, don't re-clamp.
- **Statement not yet materialized though its cycle has closed**: either call
  `StatementRepository.materializeIfDue` on view load (the app already
  materializes lazily — check how `CreditCardDetailScreen` triggers it) or
  compute the closed-cycle total live the same way as the current cycle.
- **Split/assigned expenses inside a cycle**: `Statement.totalAmount` is always
  the full transaction amount (see its doc), NOT `Expense.myShare`. Keep the
  cycle "total spending" as the full amount; if you also want a "your share"
  line, derive it from `myExpensePortionsProvider`
  (`lib/features/expense/presentation/providers/expense_providers.dart`).
- **Multiple cards (Option A)**: each card has its own Settlement View; don't
  merge cycles across cards with different `statementDay`s.

---

## 8. Testing requirements
- Unit-test any new `StatementPeriodCalculator` helpers deterministically with
  an injected `now` (existing tests in
  `test/features/credit_cards/` / `test/core/...` show the pattern — pass `now`,
  never rely on `DateTime.now()`).
- Test `currentCycleSpendProvider` / `previousCyclePendingProvider` with a
  `FakeFirebaseFirestore` seeded with a card, a `CreditCardProfile`
  (statementDay 17, paymentDueDay 5), transactions spanning two cycles, and a
  closed `Statement` with a partial payment — assert the current total excludes
  last cycle's transactions and the pending equals the prior statement's
  `remainingAmount`.
- Run `flutter analyze` (must be clean) and the full `flutter test` suite.
- Verify live via the `run` skill / real device (the user runs their own
  Firebase account — hand off the walkthrough as before).

---

## 9. Open questions to resolve during planning
1. §5 scope: per-card only vs. add a global financial month. **Confirm first.**
2. Is the Settlement View a section embedded in `CreditCardDetailScreen`, or its
   own pushed screen with a route? (Recommend embedded first; extract later if
   it grows.)
3. Cycle switcher UX: prev/next chevrons vs. a scrollable month strip vs.
   reusing the existing statements list on the card detail screen.
4. Should "this month's spending" show the **full** transaction total, the
   user's **own share** (net of split/assigned expenses), or both lines?
   (Recommend: full total as the headline, "your share" as a secondary line
   only if it differs.)

---

## 10. Definition of done
- A Settlement View that, for a card with statementDay 17 / paymentDueDay 5,
  shows this cycle's live spending total, last cycle's unpaid carryover, the due
  date, a status pill, and a newest-first breakdown of the cycle's
  transactions, with a way to page through previous cycles.
- All copy is plain-language.
- No cycle math, totals, or due-date logic duplicated from the credit-cards
  feature — everything derives from `StatementPeriodCalculator` / `Statement`.
- `flutter analyze` clean, full test suite green, new logic covered by tests.
