# Bug Investigation Report — People / Split Expense flow

**Scope:** four complaints raised while testing the redesigned People → Expense
flow and the credit-card screens. Each is documented below with the symptom,
the root cause found in the code, the fix applied, the files touched, and the
verification status.

**Overall status at time of writing:** `flutter analyze` → 0 issues;
`flutter test` → 437 passed (3 new). All four items resolved except #3, which
was a design clarification (confirmed working as intended) plus UX improvements.

---

## 1. Expense Details screen showed a blank background

- **Complaint:** "in expense detail seeing bug that background colors is blank."
- **Where:** `PersonExpenseDetailScreen` (the People-flow Expense Details screen,
  `lib/features/people/presentation/screens/person_expense_detail_screen.dart`).
- **Root cause:** two issues stacked:
  1. The `Scaffold.backgroundColor` was set to a **semi-transparent** color
     (`surfaceContainerHighest.withValues(alpha: 0.4)`). That pattern was copied
     from `TransactionDetailScreen`, but this screen is pushed with a plain
     `MaterialPageRoute` (not a go_router page); the transparent fill let the
     empty route backdrop show through, which reads as a blank/washed-out
     background where the white `AppCard`s don't stand out.
  2. The delete-warning footer used `context.colors.tertiaryContainer`, a
     ColorScheme role the app's theme (`app_theme.dart`) never defines — so it
     fell back to Flutter's default M3 pink, off-brand.
- **Fix:** removed the `backgroundColor` override so the screen uses the theme's
  solid `scaffoldBackgroundColor` (`AppColors.lightBackground` / `darkBackground`)
  like every other screen — cards now contrast properly. Changed the footer to an
  on-brand `AppColors.warning` tint.
- **Files:** `person_expense_detail_screen.dart`.
- **Status:** ✅ Fixed. Analyze clean.

---

## 2. "Expense updated successfully" dialog appeared on cancel / back

- **Complaint:** "expense updated successfully screen in every back to nav seeing
  in there."
- **Where:** the Expense Details **Actions** list (`_ActionsCard` in
  `person_expense_detail_screen.dart`) and the shared `TransactionDetailScreen`
  actions; the dialog is `ExpenseUpdatedDialog`.
- **Root cause:** after opening any action sheet (Edit / Add Payment / Split /
  Settle), the code `await`ed the sheet and then **unconditionally** showed
  `ExpenseUpdatedDialog`. Because the sheets pop on both **save** and
  **cancel/back**, the success dialog fired even when the user changed nothing —
  so backing out of an action always showed "Expense updated successfully!".
- **Fix:** every action sheet's `show()` now returns a result — `true` only when
  a change was actually saved (`Navigator.pop(true)` on save, `false` on delete,
  `null` on cancel). Callers only show the success dialog when the result is
  `true`. The Edit path additionally detects a delete-from-form (expense no longer
  exists) and closes the detail screen instead of showing "updated".
- **Files:** `edit_expense_sheet.dart`, `record_split_payment_sheet.dart`,
  `settle_amount_sheet.dart`, `split_expense_checkbox_sheet.dart`,
  `split_expense_form_sheet.dart` (all `show()` → `Future<bool?>`, pop with a
  result); `person_expense_detail_screen.dart` and
  `transaction_detail_screen.dart` (gate the dialog on `result == true`).
- **Status:** ✅ Fixed. Analyze clean; full suite green.

---

## 3. "My Spending not calculating" after adding a split expense

- **Complaint:** "i added a split expense but i think in globaly calculation
  issues .. like my spending not calculating."
- **Where:** Dashboard **My Spending** card
  (`dashboard_my_spending_card.dart`) → providers in
  `lib/features/expense/presentation/providers/expense_providers.dart`.
- **Root cause (not a bug — intended design):** "My Spending" deliberately sums
  each expense's **`Expense.myShare`**, i.e. *your* portion, not the full bill:
  `myShare = !isSplit ? totalAmount : (meParticipant?.share ?? 0)`. So:
  - **Case A — you're in the split** (e.g. ₹1000, you ₹400 / Rahul ₹600):
    My Spending counts **₹400**, and the ₹600 shows as **Money to Receive**. ✅
  - **Case B — assigned fully to someone else** ("This person will pay", ₹1000 →
    Rahul): there is **no "Me" participant**, so `myShare = ₹0`. My Spending
    doesn't move — because that money is coming back to you; the full ₹1000 still
    left your account (account balance) and shows as **Money to Receive ₹1000**.
    This looked like "not calculating" but is correct: your personal cost is ₹0.
- **Decision (confirmed with user):** keep My Spending = **your own share**. This
  matches how a personal-finance app should separate "what I spent" from "money
  coming back."
- **Follow-up UX (done under #4):** to make the two numbers obvious *before*
  saving, a live preview now shows Total / Your Spending / Money You'll Get Back.
- **Status:** ✅ Confirmed correct; UX clarified via #4. No calculation change.

**Reference — the numbers, per the user's spec:**

| Scenario | Total | Your Spending | Money to Receive | Ledger |
|---|---|---|---|---|
| You ₹400, Rahul ₹600 | ₹1000 | ₹400 | ₹600 | Rahul owes you ₹600 |
| Rahul ₹1000 (fully assigned) | ₹1000 | ₹0 | ₹1000 | Rahul owes you ₹1000 |

Both are already produced by the existing engine (`Expense.myShare`,
`totalPendingSplitAmountProvider`, per-person ledger) — no duplicate logic added.

---

## 4. Split Expense form should "just work" (live preview, wording, validation)

- **Complaint / spec:** the app "asks implementation questions instead of
  automatically handling real-world scenarios"; wants a **live preview before
  saving**, **beginner-friendly wording**, and **validation**, reusing the
  existing split engine.
- **What already satisfied the spec (verified, unchanged):**
  - My Spending / Money to Receive — `Expense.myShare` +
    `totalPendingSplitAmountProvider` (see #3).
  - Person screen totals — `PersonExpenseStatsCard` (You will receive / Total
    Settled / Total Spent) + `PersonStatementHeader`.
  - History badges — `HistoryTile` + `ExpenseStatusPill`
    (Pending / Partial / Overdue / Paid).
  - Settlement math — `ExpenseRepository.settleParticipant` (unchanged).
- **What was added:**
  1. **Live "before you save" preview** in `SplitExpenseFormSheet`: a card
     showing **Total Expense**, **Your Spending**, **Money You'll Get Back**, and
     **Split Between** (each person's share). Recomputed on every change from the
     same `ExpenseRepository.resolveShares` the save uses, so preview == result.
  2. **Friendlier wording:** "Split Between", "Your Spending", "Money You'll Get
     Back", "Here's how it works out" — no accounting jargon (project rule).
  3. **Duplicate-participant validation** in the shared `resolveShares` engine
     (so every split path gets it): the same tracked person, or the same
     free-text name (case-insensitive), can't be added twice — friendly message
     "{name} is already in this split". Existing validation (empty list, shares
     ≠ total, non-negative, percentage ≠ 100%) was already present.
- **Files:** `split_expense_form_sheet.dart` (preview card + wording + initial
  preview on prefilled forms), `expense_repository.dart` (`resolveShares`
  duplicate check).
- **Tests:** 3 new `resolveShares` tests (duplicate person, duplicate free-text
  name case-insensitive, tracked+free-text same name allowed).
- **Status:** ✅ Done. 437 tests pass.

---

## Verification summary

| Check | Result |
|---|---|
| `flutter analyze` | 0 issues |
| `flutter test` | 437 passed (was 434; +3 duplicate-participant tests) |
| Live device walkthrough | Handed to user (real Firebase account) |

## Notes / not-yet-done

- The **Monthly Settlement View** (Part B — this-cycle spending, carryover,
  category breakdown, payment progress, billing timeline) remains planned but not
  started; see `docs/monthly-settlement-view-task.md`.
- The split-expense **live preview** was added to `SplitExpenseFormSheet` (the
  "Share with several people" form). The simpler `AssignExpenseSheet` ("this
  person will pay") does not yet show the preview — low priority since an
  assignment is always "your spending ₹0, money to receive = full amount".
