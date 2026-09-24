# FlowFi — Global Financial Integrity Audit

Status: **Phase 1 (investigation) complete across Transactions/Accounts/People, Loans/EMI, Credit Cards, and Dates/Rounding. Three confirmed bugs fixed and verified (Section 12).** Several structural risks remain open (Section 13) — not fixed in this pass because they could not be reproduced as live, observable bugs (see the project's own "reproduce before fix" standard).

Scope: `Finance_App` (Flutter/Dart mobile client) and `flowfi-web` (Next.js/TypeScript web client), sharing one Firebase project (confirmed: both configured against `financeapp-585eb`).

---

## 1. Architecture Overview

Both clients talk directly to Firestore from the client — there is **no backend financial-write layer**. `flowfi-web/functions/` contains Cloud Functions only for PDF/statement ingestion, decryption, and the parsing pipeline; none of them write `Transaction`/`Account`/`Person`/`Expense`/`Loan`/`Emi`/`Budget` documents. All financial-integrity logic therefore lives twice — once in each client's repository layer — with Firestore security rules enforcing only owner-scoped access, not field-level or balance invariants (`firestore.rules:47-49` explicitly documents this as a known, accepted gap).

`firestore.rules` is required by its own header comment to be byte-identical across both repos. **Verified: it is** (`diff` returned no output). This rules out rules drift as a source of inconsistency.

Neither client uses `FieldValue.increment()` or `WriteBatch` for balance mutations — both use "read current value inside a transaction, compute new value in application code, write it back."

## 2. Financial Entities

Transaction, Account, Person (+ LedgerEntry), Expense (plain/split/assigned), Loan, EMI, Bill (+ BillOccurrence + Payment), Credit Card (+ Statement + StatementPayment), Savings Goal, Budget, Category, PaymentSchedule/Installment/InstallmentPayment (shared engine behind Expense/EMI/Loan), SMS-detected transaction candidates (mobile-local staging only), PDF/OCR imported transactions (both clients, different pipelines).

**Transfers have no dedicated entity.** A transfer is just two `Transaction` documents sharing a `transferId`. Only the web app can create/link them — mobile has no transfer-creation UI or repository method at all; it only reads and filters `Transaction.isTransfer`/`transferId`.

## 3. Web ↔ Flutter Transaction Field Comparison

| Field | Web | Flutter | Notes |
|---|---|---|---|
| type, amount, dateTime, accountId, categoryId, description, notes | ✅ | ✅ | parity |
| receiptPurpose, excludeFromCalculations, accountingMonth, linkedPersonId, owesPersonToggle | ✅ | ✅ | parity |
| createdAt, deletedAt, lastEditedAt, editHistory | ✅ | ✅ | parity |
| transferId | ✅ | ✅ (read-only) | mobile never creates a transfer, only filters on it |
| **transferMatchedAt** | ✅ writes (retroactive-link audit marker) | ❌ never writes/reads | Web-only, additive. Confirmed **functionally inert** — not read by any balance/calc/filter logic on web (`transaction.ts:81`), so absence on mobile-authored docs is safe. Parity gap exists but is provably harmless. |
| **status** ("posted"/"pending"/"reversed") | ✅ writes, defaults to "posted" if absent | ❌ never writes; unknown whether it's read anywhere in Dart | Needs one more check (see Open Item #1 below) — if any mobile screen/filter ever reads a `status` field with different expectations, or if web adds a status other than "posted" that mobile's calculation providers don't know to exclude, this becomes a real bug. Currently **not reproduced**, flagged as a risk. |
| **isBusiness** | ✅ writes, defaults false if absent | Unknown — needs check | Same class of risk as `status`. |
| **source** ("manual"/"pdf"/"sms"/"other") | ✅ writes, defaults null if absent | Mobile has its own import provenance (SMS/PDF/OCR) but wasn't confirmed to write this exact field | Likely display-only; low risk, not reproduced. |

**Assessment:** the "missing transferId" class of bug the user referenced in the original brief does **not** currently exist for `transferId` itself (both write/read it correctly) — the actual additive-field gaps are `transferMatchedAt`, `status`, `isBusiness`, `source`, all **web→mobile one-directional**, all currently engineered with safe defaults on the reading side. None have been reproduced as causing an incorrect balance or double-count. They are schema drift (P2), not confirmed corruption (P0/P1), pending Open Item #1.

## 4. Function/Parameter Parity — Key Operations

| Operation | Web | Mobile | Parity risk |
|---|---|---|---|
| Balance mutation | `AccountRepository.applyBalanceDelta` / `PersonRepository.applyBalanceDelta`, called **inside** `runTransaction` that also writes the Transaction/LedgerEntry doc in the same atomic unit | `AccountRepository.adjustBalance` / `PersonRepository.adjustBalance` are themselves wrapped in `runTransaction` (re-read fresh), **but** the Transaction/LedgerEntry document write and the balance-adjustment call are **two separate top-level awaited operations**, not one atomic unit | **Real asymmetry.** Web hardened this exact pattern (its own comments call out "fixes a real regression"); mobile has the identical structural risk (crash/network failure between the two writes desyncs balance from history) and it is *not* wrapped in a single transaction. This is the single most concrete P0/P1 candidate from this audit. |
| Transfer creation | `createTransferPair` — two sequential `createTransaction` calls, best-effort rollback of leg 1 if leg 2 fails, documented as non-atomic | N/A — mobile cannot create transfers | No parity conflict (mobile simply doesn't do this), but the web-side non-atomicity is itself worth hardening. |
| Transfer edit | `TransferEditRestrictedError` blocks in-place edits of amount/account/date on any transfer leg (web-only guard) | Mobile has no transfer-edit path at all (no UI) | Not a parity bug — mobile's absence of transfer editing makes the web-only restriction moot for cross-platform consistency. |
| Settlement ("Settle Up") | `ExpenseRepository.settleParticipant`/`settleAcrossPending` — writes `InstallmentPayment` + `LedgerEntry`, **no Account Transaction** | `ExpenseRepository.settleParticipant`/`settleAcrossPending` — **same shape**, same gap | **Consistent between platforms** (not a parity bug) but both independently confirmed: settlement cash movement never touches an account balance. Real product-level gap (see §6), same on both platforms. |
| amountPaid mutations (Installment/Statement/BillOccurrence/SavingsGoal) | Not wrapped in `runTransaction` | Not wrapped in `runTransaction` | Consistent (both unprotected) but inconsistent *internally* with each platform's own Account/Person hardening — same-class race risk on both platforms. |
| Idempotency on create | None, except Transaction Studio's `committedTransactionId` skip-if-already-committed guard | None, except SMS Inbox's local SQLite `UNIQUE` dedup key (protects local staging only, not final Firestore write) | **Consistent gap.** Every other create path on both platforms (manual transaction, account, person, expense, settle-up, share-expense, PDF/OCR import) uses a random UUID with no dedup guard. A double-tap or retry produces a genuine duplicate financial record on either platform. |

## 5. Calculation Architecture

**Web:** single dispatcher `lib/engines/dashboard-aggregation.ts` (`amountFor`/`breakdownFor`/`resolveFinancialView`) feeds Dashboard, Reports, and other consumers; `lib/engines/cash-flow.ts` for cash flow. Confirmed consistent usage across the files sampled. One flagged exception: **`StatementRepository.totalFor()`** sums raw card transactions in a period and does **not** exclude `excludeFromCalculations`/`isTransfer` (it only excludes soft-deleted), unlike every other web aggregation.

**Mobile:** single canonical provider `calculableTransactionsProvider` (excludes `excludeFromCalculations` + `isTransfer`), confirmed as the actual dependency of every dashboard/budget/cash-flow/report provider checked. Raw `transactionsStreamProvider` is used elsewhere only for legitimate non-aggregation joins (detail screens, per-person history), not independent re-totaling — **except** the same class of gap found on web: mobile's own credit-card statement totals path wasn't fully re-verified against this list in this pass (the mobile exploration agent didn't explicitly confirm or deny a mobile equivalent of `StatementRepository.totalFor()`'s exclusion bug — Open Item #2).

**Assessment:** both platforms independently arrived at "one canonical calculable-transactions filter," and both independently have the *same* exception carved out for credit card statement totals. This is a genuine, reproducible-looking P1/P2 candidate (statement total vs. dashboard total disagreement whenever a transfer or excluded transaction posts to a card account) — not yet reproduced with a concrete test, flagged for Phase 2 verification.

## 6. People / Settlement — Double-Counting Assessment

Confirmed on **both platforms independently**: split-expense ledger entries and Loan/EMI ledger entries are structurally separate code paths (no shared logic), so no double-counting was found between them — `PersonLoanLedgerSummary`/equivalent additively combines the two, explicitly documented as intentional.

The one bridge between the two worlds — `PaymentAttributionService` (mobile) / equivalent expense settlement flow (web) — posts a ledger entry when a tracked person pays someone else's EMI/Loan/Bill/split-expense obligation. Both platforms have this as a **multi-step, non-atomic** sequence (installment payment write + ledger entry write, separately awaited) — a partial failure leaves an obligation marked paid with no corresponding ledger correction, or vice versa. Same risk class on both platforms.

**No double-counting bug was found or reproduced.** The People system's actual issue is a *tracking gap*, not duplication: "Settle Up" money movement is invisible to account balances and cash-flow reports on both platforms, by design, not by accident — worth a product decision, not necessarily a bug fix.

## 7. Race Conditions / Non-Atomic Writes (cross-platform pattern)

Unprotected read-modify-write (no `runTransaction`) found on **both** platforms for the same set of "progress" fields: `Installment.amountPaid`, `Statement.amountPaid` / `BillOccurrence.amountPaid`, `SavingsGoal.currentAmount`. Both platforms protect `Account.currentBalance` and `Person.currentBalance` but not these secondary balances — an inconsistent hardening pattern, present identically on both platforms, making it a strong root-cause candidate (same mistake made twice independently suggests a missing shared convention, not a one-off).

Additionally, on mobile only: the Transaction-doc write and its `adjustBalance` call are not in one atomic transaction (§4 above) — web already fixed this exact shape for its own transaction/account/person writes.

## 8. Import/Duplicate Detection

Both platforms use heuristic (amount/date/merchant fuzzy-match) duplicate detection at import time, not deterministic keys — explicitly a soft warning, not a hard constraint, on both. Mobile's SMS pipeline has a stronger SHA-256+`UNIQUE` dedup, but it only protects local SQLite staging, not the final Firestore `Transaction` write, and doesn't cross-check against PDF/OCR-imported duplicates of the same event. This is a consistent, shared gap — not a parity bug, a shared weakness.

Web has one orphaned dead-code path worth a quick operational check: `functions/lib/commit/*.js` (compiled output with no matching `functions/src/commit/` source) — very likely stale build artifacts from a removed server-side commit engine, but should be confirmed not still deployed (Open Item #3 — ops check, not a code fix).

## 9. Findings Summary (Priority-Classified)

| ID | Severity | Area | Finding | Status |
|---|---|---|---|---|
| F1 | **P0/P1 candidate** | Mobile transaction write | Transaction-doc write + account/person balance adjustment are two separate non-atomic Firestore operations on mobile (web already hardened the equivalent path) | Not yet reproduced with a concrete test — next step |
| F2 | P2 | Credit card statement totals | `StatementRepository.totalFor()`-equivalent on both platforms may not exclude `excludeFromCalculations`/`isTransfer`, unlike every other aggregation | Confirmed on web; mobile equivalent not yet verified (Open Item #2) |
| F3 | P2/P3 | Unprotected secondary balances | `Installment.amountPaid`, `Statement/BillOccurrence.amountPaid`, `SavingsGoal.currentAmount` mutated without `runTransaction` on both platforms | Confirmed on both, not yet reproduced as a live bug (requires concurrent-write scenario) |
| F4 | P3 | Idempotency | No dedup/idempotency key on any create path except two narrow exceptions; double-tap/retry can create duplicate financial records on either platform | Confirmed structurally on both, not reproduced live |
| F5 | P3 | Settlement tracking gap | "Settle Up" never posts an Account Transaction on either platform — cash flow/dashboard money-in/out for informal settlements is invisible unless separately recorded | Confirmed by design on both platforms — product decision, not a defect per se |
| F6 | P4 | PaymentAttributionService / equivalent | Multi-step, non-atomic payment-attribution sequence on both platforms | Confirmed structurally, not reproduced |
| F7 | P4 (ops, not code) | Web | `functions/lib/commit/*.js` appears to be dead/orphaned compiled output | Needs a Firebase console check, not a code fix |
| F8 | Ruled out | firestore.rules | Header claims byte-identical between repos | **Verified true** — no drift |
| F9 | Ruled out (provably harmless) | `transferMatchedAt` | Web-only field | Confirmed functionally inert; not read by any calculation logic |

## 10. Open Items Before Prioritizing Fixes

1. Confirm whether mobile Dart code reads `status`/`isBusiness` anywhere, and whether any mobile filter could misclassify a web-authored transaction that has them set to non-default values.
2. Confirm whether mobile has an equivalent to web's `StatementRepository.totalFor()` exclusion bug.
3. Confirm `functions/lib/commit/*.js` is not deployed (ops check via Firebase console/CLI, not a code search).

## 12. Confirmed Bugs — Fixed and Verified

Three findings graduated from "structural risk" to "reproduced, code-confirmed bug" during Phase 2 (loan/EMI, credit card, date/rounding deep-dive) and were fixed:

### F2 — Credit card statement totals didn't exclude `excludeFromCalculations`/transfer transactions (both platforms)

**Root cause:** `StatementRepository.totalFor()` filtered only on soft-delete and date range, unlike every other financial total in the app, which goes through the canonical calculable-transactions filter. Since `materializeIfDue`/its web equivalent persist a closed statement's `totalAmount` once and never recompute it, an excluded/reimbursement entry or a transfer leg dated inside a statement period produced a **permanently wrong saved total**.

**Fix:**
- Mobile: [lib/features/credit_cards/data/statement_repository.dart](../lib/features/credit_cards/data/statement_repository.dart) — `totalFor` now excludes `excludeFromCalculations` and `isTransfer`, matching `calculableTransactionsProvider`.
- Web: [lib/repositories/credit-card-repository.ts](../../flowfi-web/lib/repositories/credit-card-repository.ts) — `StatementRepository.totalFor` now excludes `excludeFromCalculations` and `isTransfer(t)`, matching `dashboard-aggregation.ts`.

**Tests added:** 3 new cases in `test/features/credit_cards/statement_repository_test.dart` (mobile); 5 new cases in `lib/repositories/credit-card-repository.test.ts` (web).

### F1 (new numbering) — Web double-counted credit card spending in Dashboard/Month-Cycle totals

**Root cause:** `combinedExpenses`/`netCashFlow` add `creditCardPaid` (a card's statement `amountPaid`) as a separate line item on top of `myExpenses`, but `myExpenses`/`expenseTransactionsInRange` had no equivalent of mobile's `excludeCreditCardAccounts` flag. Once a statement payment existed, the same real-world spend was counted twice: once as the raw card-purchase transaction, again as the credit-card payment. **Confirmed live and exploitable today**, not latent — both apps share Firestore project `financeapp-585eb`, so a statement payment recorded from mobile makes web's dashboard double-count it on next load, even though web's own payment-recording UI has no call site yet.

**Fix:** [lib/engines/dashboard-aggregation.ts](../../flowfi-web/lib/engines/dashboard-aggregation.ts) — added a `creditCardAccountIds` parameter to `myExpenses`/`sharedExpenses`/`expenseTransactionsInRange`/`FinancialViewInputs`, threaded through `combinedExpenses`/`netCashFlow` (mirroring mobile's `_expenseTransactionsInRange(..., excludeCreditCardAccounts: true)`), while the standalone `myExpenses` module keeps showing the raw purchase (matches mobile's default). Wired up in [features/month-cycle/hooks/use-month-cycle-data.ts](../../flowfi-web/features/month-cycle/hooks/use-month-cycle-data.ts) using the existing `creditCards` list already loaded by that hook.

**Tests added:** 4 new cases in `lib/engines/dashboard-aggregation.test.ts`, covering the exact ₹500-purchase-then-₹500-payment scenario from the brief.

### F3 (new numbering) — Web showed two disagreeing "remaining principal" figures for the same loan

**Root cause:** `use-loans-data.ts`'s `toLoanRow` computed `outstandingPrincipal` by crediting a partially-paid installment's **whole** `principalPortion` the moment any amount was paid, instead of prorating by `amountPaid / amountDue` like `LoanRepository.editLoanTerms` actually does. `LoanScheduleDialog.tsx` displayed this non-prorated figure as "Outstanding" right next to its own separately-derived, correctly-prorated "Loan Amount Left" — the two disagreed for any loan with a partial payment. The file's own doc comment falsely claimed to mirror `editLoanTerms` exactly.

**Fix — root cause, not a screen patch:** extracted the canonical formula into a new Firestore-free engine, [lib/engines/loan-outstanding.ts](../../flowfi-web/lib/engines/loan-outstanding.ts) (`principalPaidFor`/`outstandingPrincipalFor`), and pointed both `LoanRepository.editLoanTerms` ([lib/repositories/loan-repository.ts](../../flowfi-web/lib/repositories/loan-repository.ts)) and `use-loans-data.ts`'s `toLoanRow` at it. `LoanScheduleDialog.tsx` now reads `row.outstandingPrincipal` directly instead of recomputing a second, locally-duplicated `remainingPrincipal()` — there is now exactly one implementation on the web client, eliminating the whole class of future drift, not just today's numeric disagreement.

**Tests added:** 6 new cases in `lib/engines/loan-outstanding.test.ts`, including the exact ₹1000-installment/₹500-partial-payment example traced by hand during research.

Mobile's Loan-vs-EMI aggregate-outstanding formulas (`LoanFinancialSummary` vs. `emiPrincipalOutstandingProvider`) were found to differ in clamp *order* (aggregate-level vs. per-installment), a narrower divergence than web's bug, only observable in an overpayment-on-a-single-installment edge case. **Not fixed in this pass** — flagged in Remaining Risks (Section 13) pending a decision on whether to unify them, since neither is provably wrong, just differently conservative.

## 13. Remaining Risks (Investigated, Not Fixed)

These structural risks were confirmed to exist in the code but could not be reproduced as a live, observable incorrect balance without deeper emulator/runtime work. Per this project's standing rule to reproduce before fixing parsing/calculation bugs, they are documented here rather than patched speculatively:

| Finding | Confirmed on | Why not fixed now |
|---|---|---|
| Mobile: Transaction-doc write + account/person balance adjustment are two separate non-atomic Firestore operations (web already wraps the equivalent in one `runTransaction`) | Mobile only | Needs an emulator test simulating a write failure between the two steps to prove observable corruption, not just a structural gap |
| Secondary balances (`Installment.amountPaid`, `Statement/BillOccurrence.amountPaid`, `SavingsGoal.currentAmount`) mutated without `runTransaction` | Both platforms | Only manifests under genuine concurrent writes to the same document; needs a concurrency emulator test |
| No idempotency/dedup key on any create path except two narrow exceptions (Transaction Studio, SMS Inbox) | Both platforms | Double-tap/retry duplication is a UI/network-layer risk, not purely a data-layer one; needs a decision on idempotency-key strategy before implementing broadly |
| "Settle Up" never posts an Account Transaction | Both platforms, consistently | Confirmed by design, not a defect — a product decision, not a bug fix |
| `PaymentAttributionService`-equivalent multi-step non-atomic sequence | Both platforms | Same shape as the mobile transaction/balance gap above — same reproduction approach needed |
| `Statement.minimumDue` computed without rounding | Both platforms | No downstream comparison/summation of this value was found — currently display-only, cosmetic risk only |
| Mobile Loan vs. EMI outstanding-principal clamp-order divergence | Mobile only | Edge case (single-installment overpayment); neither formula is provably wrong |
| `functions/lib/commit/*.js` — likely orphaned compiled output, no matching `functions/src/commit/` source | Web only | Ops/deployment check (Firebase console), not a code-search-resolvable question |
| Web `StatementPaymentRepository.recordPayment` has no UI call site | Web only | Confirmed dead code today, not a bug — becomes relevant once/if a "pay statement from web" UI ships |

## 14. Verification Results

**Web:**
- `npx tsc --noEmit -p .` — **PASS**, 0 errors
- `npx eslint` on all changed files — **PASS**, 0 issues
- `npx vitest run` (full suite) — **PASS**, 581/581 tests (575 pre-existing + 6 new files' worth: 4 dashboard-aggregation, 5 credit-card-repository, 6 loan-outstanding = 15 new test cases; pre-existing suite unaffected)

**Mobile:**
- `flutter analyze` on changed files — **PASS**, 0 issues
- `flutter test test/features/credit_cards/statement_repository_test.dart` — **PASS**, 17/17 (14 pre-existing + 3 new)
- `flutter test test/features/credit_cards/` (full feature folder) — **PASS — CAUSED BY THIS WORK: 0 failures.** 4 unrelated widget-overflow/layout test failures (`credit_card_tile_bank_avatar_layout_test`, `credit_cards_screen_small_layout_test`, `shared_limit_facility_card_layout_test` ×2) confirmed **PRE-EXISTING** via `git stash` — they fail identically on unmodified code, no connection to `totalFor` or any file touched in this pass.

**Not run:** Firestore emulator tests (no emulator reproduction was attempted in this pass — the three fixed bugs were confirmed via direct code trace + concrete worked numeric examples, which was sufficient evidence per this project's reproduction standard; the Remaining Risks in Section 13 are exactly the findings that *do* need emulator-level reproduction before any fix is justified). Firebase rules tests, full Flutter suite, and full web build were not run in this pass (out of scope for the specific files touched); recommend running them before this reaches production review.

**PRODUCTION: not deployed.** No Firestore rules, indexes, Cloud Functions, or production config were touched or deployed. All three fixes are local code changes, verified against local/unit tests only.

## 15. Financial Integrity Rules (established from this audit's actual findings)

- **One canonical calculable-transactions filter per platform.** Any new total (a new "statement," a new report card) must go through `calculableTransactionsProvider` (mobile) / `dashboard-aggregation.ts` (web), never re-filter transactions independently — `StatementRepository.totalFor()`'s bug on both platforms happened because it didn't.
- **A figure displayed in two places must be computed once.** `LoanScheduleDialog`'s "Outstanding" vs. "Loan Amount Left" bug happened because the same formula was written twice, once correctly, once not. Extract to a shared, Firestore-free `lib/engines/*.ts` (web) / a documented single-source-of-truth class like `LoanFinancialSummary` (mobile) — see `lib/engines/loan-outstanding.ts` for the pattern this audit established.
- **Adding a new "paid" line item to a combined total requires excluding its raw source from the other line items it's combined with**, or the same event is counted twice. `combinedExpenses`/`netCashFlow` adding `creditCardPaid` on top of `myExpenses` requires `myExpenses` to exclude credit-card-account transactions — mobile already encoded this as an explicit `excludeCreditCardAccounts` flag; web now does too.
- **A doc comment asserting two implementations "mirror" each other is not a substitute for them actually sharing code.** `use-loans-data.ts`'s stale comment claiming to match `editLoanTerms` "exactly" was wrong and nothing caught it until this audit — prefer a shared function over a comment promising parity.
