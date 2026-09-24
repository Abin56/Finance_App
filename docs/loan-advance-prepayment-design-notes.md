# Loan/EMI Advance & Prepayment — Reversal, Additional Disbursement, Person-Ledger Design Notes

Status: **investigation only — nothing in this document is implemented.** Written to satisfy the "design and verify before UI" checkpoint. Applies identically to `Finance_App` (Dart) and `flowfi-web` (TS) — both must implement whatever is eventually built here the same way, mirroring the pattern established for `LoanAdvancePaymentRepository.record`/`_reamortize`.

---

## 1. Reversal architecture (investigation — not implemented)

### 1.1 Regular/advance payment reversal

**What must reverse, atomically, inside one Firestore transaction (mirrors the existing `record()` core exactly — same shape, opposite direction):**

1. `InstallmentPayment` — soft-delete (not hard-delete; `permanentlyDeletePayment` stays a separate, later step, same convention `InstallmentPaymentRepository.softDeletePayment`/`restorePayment` already use elsewhere in the app).
2. `Installment.amountPaid` — reverse by the reversed payment's own `amount` (re-read fresh inside the transaction, same clamp-to-`[0, amountDue]` as the forward path).
3. Linked `Transaction` — soft-delete via the now-atomic `softDeleteTransactionInTransaction` (already built and composable — this is exactly what it's for).
4. `Account.currentBalance` — reversed automatically as part of step 3's atomic core (that method already reverses the balance effect).

**Design decision needed before implementation:** should this be a new `LoanAdvancePaymentRepository.reversePayment(payment)` method, or should it live on `InstallmentPaymentRepository` (the existing non-atomic reversal home)? Recommendation: **on `LoanAdvancePaymentRepository`**, not `InstallmentPaymentRepository` — the whole point of this feature was moving loan/EMI payments off the old non-atomic path; adding a new atomic reversal method to the old repository would reintroduce a second, inconsistent write path for the same kind of event. Keeps constraint #1 from the last task's brief intact: one repository, one entry point, for every loan/EMI payment lifecycle operation including reversal.

**Overflow (ledger-only) payment doc:** if the payment being reversed had `allocationType == principalPrepayment` with a ledger-only sibling doc (the `_principal`-suffixed one), reversing it is **not** a simple soft-delete — see §1.2, since undoing a prepayment also means undoing its re-amortization.

### 1.2 Principal-prepayment reversal

More involved because a successful prepayment already triggered `_reamortize`'s `writeBatch`: soft-deleted the original "untouched" tail, generated a brand-new tail, updated `Loan.installmentCount`, updated `PaymentSchedule`, wrote a `LoanReamortizationEvent`.

**What must happen, in order:**

1. **Atomic core reversal** (§1.1's steps, run first) — reverses the regular fan-out portions and the linked `Transaction`/`Account` delta. The ledger-only overflow payment doc reverses too (soft-delete; it never touched `amountPaid` so there's nothing to un-apply there beyond the doc itself).
2. **Re-amortization reversal** (`writeBatch`, mechanical inverse of `_reamortize`):
   - Soft-delete every installment `_reamortize` **generated** (the new tail) — these are identifiable via the `LoanReamortizationEvent` (need a new field, see below, or by re-deriving "installments with `sequenceNumber > installmentCountBefore` on this schedule, created after `event.createdAt`" — the explicit FK is safer and should be added rather than relying on inference).
   - **Restore** every installment `_reamortize` **soft-deleted** (the original tail) — same identifiability problem. `LoanReamortizationEvent` currently has no FK list to either set of installment ids.
   - Revert `Loan.installmentCount` to `event.installmentCountBefore`.
   - Revert `PaymentSchedule.installmentCount`/`totalAmount` to their pre-event values (needs the schedule's pre-event `totalAmount` captured somewhere — not currently stored on the event either).
   - Mark `LoanReamortizationEvent.reversed = true` (field already exists, unused until now).

**Schema gap found during this investigation:** `LoanReamortizationEvent` as built captures the *numbers* (`principalBefore`/`principalAfter`/`installmentCountBefore`/`installmentCountAfter`) but not the *identities* of which installment documents were soft-deleted vs. generated, nor the schedule's pre-event `totalAmount`. Reversal cannot be built correctly without one of:
- (a) add `deletedInstallmentIds: string[]` / `generatedInstallmentIds: string[]` / `totalAmountBefore: number` to the event at write time (`_reamortize` already has all of this in scope when it writes the event — cheap to capture), or
- (b) re-derive the sets defensively at reversal time from `sequenceNumber`/`createdAt`/`deletedAt` heuristics (fragile — two reamortizations close together could make this ambiguous).

**Recommendation: (a).** This is a pure additive schema change (new optional fields, safe defaults for legacy docs = empty arrays/null, same pattern every other field in this feature has followed) — no migration, no behavior change to anything already shipped. Flagging as required before reversal can be implemented, not implementing it now per your explicit "do not implement" instruction.

**Mixed/duplicated schedule risk:** the exact failure mode you're asking about — reversing only the "regenerated tail" without correctly restoring the "original tail" (or vice versa) would leave the schedule with either a gap (fewer installments than the loan's own `installmentCount` claims) or a duplicate (both an old and new installment covering the same period). The two-step batch (delete-generated, restore-original) must be one atomic `writeBatch`, not two separate calls — a partial failure between them is exactly the "mixed schedule" the brief is worried about. Same two-unit posture as the forward path (atomic core + best-effort-sequenced batch) is *not* safe enough here on its own — the batch itself must be a single atomic unit for reversal specifically, because unlike the forward direction (where a batch failure just means "reshape didn't happen, payment still correct"), a *partial* reversal batch leaves a genuinely inconsistent schedule, not merely an un-reshaped one.

### 1.3 Retry/idempotency and partial failure for reversal

Same idempotency shape as the forward path: a reversal action needs its own client-generated idempotency key, and the reversal's own deterministic marker (e.g. a `reversedAt` timestamp already present on the payment, or a new dedicated marker doc) checked first inside the transaction before any reversal writes — mirrors `record()`'s sentinel-check-before-any-write pattern exactly. Partial failure of the atomic core (§1.1) is impossible by construction (single `runTransaction`). Partial failure of the re-amortization-reversal batch (§1.2 step 2) is the risk flagged above — requires the schema addition before it can be made safe.

**Status: design only. Not implemented on either platform. Blocks UI exposure of delete for advance/prepayment payments until built.**

---

## 2. Additional disbursement (investigation — not implemented)

`PaymentAllocationType.additionalDisbursement` exists in the enum on both platforms (schema completeness) but no repository method produces it anywhere. Per your request, defining semantics precisely before any implementation:

| Aspect | Definition |
|---|---|
| **Borrower vs. lender cash-flow direction** | Mirror of `record()`'s existing table, but *inverted* relative to a payment: for `direction: "taken"` (you borrowed), an additional disbursement is the lender giving you *more* money → **income** (account balance increases). For `direction: "given"` (you lent), it's you giving the borrower more → **expense** (account balance decreases). This is the exact opposite sign convention from a regular payment on the same loan, which is the most important semantic to get right — reusing the payment-direction table verbatim would be backwards. |
| **Account balance effect** | One signed `Transaction` + `Account.currentBalance` delta, same atomic-core shape as `record()` — this part *can* reuse the exact same primitives (`createTransactionInTransaction`/`applyBalanceDelta`), just with the sign flipped per the row above. |
| **Outstanding-principal effect** | Increases, not decreases: `Loan.loanAmount += disbursementAmount` (this is the one case where `loanAmount` legitimately changes after payments may already exist — everywhere else in the app `loanAmount` is locked post-first-payment; this needs its own explicit exception to that rule, recorded via `loan.recordEdit` same as any other field change). |
| **Transaction representation** | A new `Transaction` with `loanId` set (same FK fields as a payment) and `paymentAllocationType: "additionalDisbursement"` — but **no** `InstallmentPayment`/`installmentPaymentId`, since nothing is being *paid*; there's no installment this disbursement settles. `installmentId`/`installmentPaymentId` stay null on this Transaction, distinguishing it structurally from every payment-type transaction. |
| **Schedule/re-amortization behavior** | The opposite corner of `ReduceTenurePolicy`: a payment prepayment holds `installmentCount` roughly constant, lets the resolved tenure shrink. A disbursement should hold `installmentCount` constant and let the *installment amount* grow (recomputing via `InterestCalculator.calculate`/`calculate` over the same remaining count at the new, larger outstanding principal) — this is a **different policy**, not `ReduceTenurePolicy` reused with a negative delta. Needs its own `PrepaymentReamortizationPolicy` implementation (the interface is already designed to be pluggable for exactly this — see `PrepaymentReamortizationPolicy`/`policy.solve`'s doc comment). |
| **"HoldTenurePolicy"** | Proposed name accepted — a new policy: given `outstandingPrincipalAfter` (now *larger*) and the *existing* `installmentCount` (held fixed, not solved-for), compute the new constant installment amount directly via one `InterestCalculator.calculate` call (no iterative search needed, unlike `ReduceTenurePolicy` — the count is already fixed, only the amount is unknown, which the amortization formula gives directly). Simpler than `ReduceTenurePolicy`, no "unsolvable" case in the same sense — the only failure mode is a malformed interest config, which should still surface as an explicit outcome rather than crash, for interface consistency. |
| **Idempotency** | Same deterministic-transaction-ID sentinel scheme as `record()` — no new mechanism needed, this composes with the existing pattern. |
| **Reversal** | Blocked on §1's schema gap (needs the same installment-identity-tracking fields on the reamortization event), plus its own sign-reversal logic (undo an income becomes an expense reversal, and vice versa) — not designed further here, pending §1's prerequisite. |
| **Person-ledger effect** | See §3 — same answer as a regular payment: does not touch the person ledger directly. If the disbursement is *funded by* a tracked person (someone else is providing the additional money on the account owner's behalf), that's a separate, orthogonal fact best captured the same way `payerPersonId` already works for payments — out of scope to design further until a concrete product need names it. |

**Status: fully specified, zero lines implemented.** Recommend implementing after reversal (§1) lands, since `HoldTenurePolicy` benefits from the same schema additions.

---

## 3. Person-ledger integration (investigation — findings, no implementation)

### 3.1 Current state (both platforms, unchanged by this feature)

- `Person.currentBalance` is driven exclusively by `LedgerRepository`/`LedgerEntry` documents (mobile) and the equivalent on web — nothing in `LoanAdvancePaymentRepository` touches either.
- The **only** existing bridge between "a Person paid/is owed something" and a Loan/EMI/Bill/split-expense obligation is `PaymentAttributionService` (mobile) — it posts exactly one `LedgerEntry` (`type: borrowed`) per batch of payments when `payerPersonId != null` (someone other than the account owner paid). It never touches `Account.currentBalance` (that's the `Transaction`'s job) and never touches the obligation's own payment tracking directly (`item.record` delegates back to the module's existing repository method).
- **This service is not wired into `LoanAdvancePaymentRepository.record()` at all** — confirmed by inspection: no import, no call, no `payerPersonId` parameter on `RecordAdvancePaymentParams`/`RecordAdvancePaymentParams` (TS). This was an explicit Phase-0 scope decision, not an oversight (documented in the original safety assessment this session opened with).

### 3.2 Why this is currently safe (no double-counting), and what "authoritative path" means

Three financial facts, three disjoint fields, by construction:

| Fact | Field | Owner |
|---|---|---|
| Cash moved through an account | `Account.currentBalance` (via `Transaction`) | `LoanAdvancePaymentRepository`'s atomic core |
| A loan/EMI obligation was paid down | `Installment.amountPaid` / `Loan.loanAmount` minus principal paid | `LoanAdvancePaymentRepository`'s atomic core + `_reamortize` |
| Someone else now owes/is owed money because they fronted cash | `Person.currentBalance` (via `LedgerEntry`) | `PaymentAttributionService` (when wired) |

These three facts can coexist for the *same* real-world event (a friend pays your EMI for you) without double-counting **only if each field's write path stays exclusive to that field** — which is already true today by the simple fact that `LoanAdvancePaymentRepository` never imports or calls anything ledger-related. The risk this section is asked to rule out (`Loan`+`Transaction`+`Person ledger`+`Account` disagreeing) cannot currently manifest, because only two of the four are wired up at all for this feature.

### 3.3 What integrating `payerPersonId` would require (not implemented)

If/when this feature adds a `payerPersonId` parameter (mirroring the existing regular-EMI payment sheets' `_resolvePayer` pattern):

1. `record()`'s atomic core would need to **also** call into the ledger write — but `PaymentAttributionService.apply()`'s current design (a list of `PaymentAttributionItem`s, each with an async `record` callback) is **not composable into an existing open `tx`** the way `createTransactionInTransaction` etc. are. It calls `ledgerRepositoryFor(person.id).addEntry(...)` directly, which opens its own `runTransaction` internally (mirroring `AccountRepository.adjustBalance`'s shape) — nesting that inside `record()`'s own transaction would violate constraint #3 from the prior task ("do not introduce nested Firestore transactions").
2. **Authoritative resolution:** the ledger entry amount must be the **total signed payment amount** (`amount` param to `record()`), not separately re-derived from the fan-out portions or the prepayment overflow — one `LedgerEntry` per payment action, same "one bank movement, one ledger line" principle `PaymentAttributionService` already documents for its existing callers.
3. This means: either (a) extend `createTransactionInTransaction`-style composability to a new `addEntryInTransaction` on `LedgerRepository` (same refactor shape as this session's `transaction-repository.ts` cleanup — a composable `*InTransaction` primitive), and fold the ledger write into `record()`'s existing atomic core, or (b) keep it as a deliberate best-effort *second* step after the atomic core commits (same posture `_reamortize` already has relative to the core) — accepting that a ledger-write failure leaves the payment correctly recorded but the "who fronted the cash" fact missing, recoverable manually.

**Recommendation, not implemented:** (b) is lower-risk and matches this feature's existing two-tier atomicity philosophy (core is fully atomic; secondary consequences are best-effort-sequenced, never silently dropped, always surfaced). (a) is more correct but requires refactoring `LedgerRepository` first, out of scope for this pass.

### 3.4 Ownership summary (the "authoritative path" this section was asked to document)

- **Account balance**: owned exclusively by `Transaction` documents via `TransactionRepository`/`LoanAdvancePaymentRepository`'s atomic writes. Never derived from Person or Loan state.
- **Loan/EMI obligation state**: owned exclusively by `Installment`/`Loan` documents via `LoanAdvancePaymentRepository`. Never derived from Person or Account state.
- **Person balance**: owned exclusively by `LedgerEntry` documents via `LedgerRepository`/`PaymentAttributionService`. Never derived from Loan or Account state, and — critically — **never currently written by anything in this feature**.

No integration exists today, so no double-counting risk exists today. The risk only becomes live once `payerPersonId` is wired in, and §3.3 is the design that must be followed when that happens — not invented ad hoc at that time.

**Status: findings documented, zero lines implemented, no wiring added.**
