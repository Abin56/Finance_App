# Split Expense / Contact Ledger — Design Flow & Logic Analysis

Source: Figma screen set (11 frames) covering a contact's expense ledger, expense detail, edit/payment/split/settle flows, status system, and warning/confirmation dialogs.

This document reverse-engineers the **working flow** and **business logic** implied purely by the visual design — field-by-field, state-by-state, in the exact order the frames appear on the canvas — so it can be used as an implementation spec.

---

## 1. Screen Inventory (in canvas order)

| # | Screen | Type | Purpose |
|---|--------|------|---------|
| 1 | Contact Ledger (`Rahul Sharma`) | Full screen | Overview of one person's balance + their expense history |
| 2 | Expense Details | Full screen | Single expense's facts + action menu |
| 3 | Edit Expense | Full screen (modal-style) | Mutate an expense's core fields |
| 4 | Add Payment | Full screen (modal-style) | Record advance or settling payment against an expense |
| 5 | Split Expense | Full screen (modal-style) | Divide one expense across multiple people |
| 6 | Settle Amount | Full screen (modal-style) | Close out the remaining balance on an expense |
| 7 | Expense Updated | Dialog | Success confirmation + shortcut actions |
| 8 | Status Indicators | Legend (not a real screen) | Defines the 4-state status vocabulary |
| 9 | Quick Notes | Helper copy | User-facing explanation of the feature |
| 10 | Tips | Helper copy | Discoverability hint (long-press) |
| 11 | Warning & Confirmation Messages | Dialog set | 4 guardrail dialogs used across the flow |
| — | Privacy footer | Persistent footer/card | On-device storage reassurance |

---

## 2. Screen-by-Screen Breakdown

### 2.1 Contact Ledger screen
- **Header**: back button, contact name, overflow menu (likely: edit contact, delete contact, share/export).
- **Balance summary card**, two rows of two stats:
  - `You will receive` — ₹2,450 (green) — the *net pending* amount this person still owes.
  - `Total Settled` — ₹3,550 — cumulative amount already collected from this person, all-time.
  - `To Receive` — a status-style pill, not the number itself — likely a redundant label/tag rather than a separate figure (or the section header for the number above it).
  - `Total Spent` — ₹6,000 — cumulative amount ever paid on this person's behalf (Total Settled + You will receive should reconcile against this, i.e. `Total Spent = Settled + Pending`, since 3,550 + 2,450 = 6,000 exactly). **This is the core reconciliation identity the whole screen is built on.**
- **Tabs**: `History` (default/active) · `Summary` · `Payments` — three views over the same underlying expense set:
  - *History* = chronological list of expenses (what's shown).
  - *Summary* = presumably aggregated stats/breakdown (by category, by month, etc.) — not detailed in this frame.
  - *Payments* = presumably a flat list of payment transactions only (as opposed to expenses) — mirrors the "Payments" tab pattern common in ledger apps.
- **Grouped list** (by month, e.g. "June 2025"), each row showing:
  - Emoji/category icon, description, amount (right-aligned)
  - Date + a fixed descriptor `To Receive` + a status pill (`Pending` / `Settled ✓` / `Partial`)
  - Implies each list row's status pill is one of the 4 canonical statuses (§4).
- **Primary CTA**: `+ Add Expense` (full-width, filled button) — the single entry point for creating new expenses against this contact.
- **Inline hint**: "Tap on any expense to view details, edit, add payment or split." — confirms the row's `onTap` target is the Expense Details screen (2.2), and that Edit/Add Payment/Split are *reachable from there*, not from this list directly (though the Tips panel later says long-press gives "quick actions" — a secondary, faster path to the same actions without navigating in).
- **Bottom navigation**: Dashboard / History / **People** (active) / Bills / More — confirms this ledger is nested under a top-level "People" section of the app, not its own tab.

### 2.2 Expense Details screen
- **Header**: back, title "Expense Details", overflow menu (likely duplicates the Actions list below, or holds Share/Export).
- **Hero block**: icon, description, big amount, and a **status pill** in the top-right corner of the amount row — status is a first-class, always-visible attribute of an expense, not something buried in a menu.
- **Metadata grid**: `Paid by` / `Category` / `Note` — read-only facts about the expense.
- **Highlighted callout**: "`Rahul Sharma` owes you `₹1,200`" — a plain-language restatement of the amount, using the *contact's name* instead of "remaining" — this is the pattern the rest of the app should follow for plain-language framing (state this explicitly if the codebase has a "no accounting jargon" UI rule).
- **Actions list** (the operational core of this screen), in this exact order:
  1. **Edit Expense** → screen 2.3
  2. **Add Payment** ("Add advance or partial payment") → screen 2.4
  3. **Split Expense** ("Split this expense with others") → screen 2.5
  4. **Settle Amount** ("Mark as fully settled") → screen 2.6
  5. **Delete Expense** (visually distinct, red/destructive) → confirmation dialog (§2.11)
- **Persistent warning footer**: "Deleting this expense will also remove all related payments and cannot be undone." — this is shown *unconditionally* on this screen (not just inside the delete dialog), acting as an ambient warning before the user even taps Delete. Implies a **cascade-delete** contract: Expense → its Payments/Installments → any downstream ledger effect.

### 2.3 Edit Expense screen
- **Header pattern**: `Cancel` / title / `Save` — standard modal-form chrome (distinct from the "back + kebab" pattern of full screens), signaling this is a transient editing context that can be discarded.
- **Fields**: Title (with emoji/icon prefix baked into the text field itself — interesting: the emoji appears to be *part of the title string*, not a separate icon picker), Amount, Date (with calendar picker affordance), Category (chevron → picker), Note (optional, multi-line).
- **Destructive action embedded in the edit form**: a full-width `Delete Expense` button at the bottom — so deletion is reachable from *both* the Actions list (2.2) and the edit form (2.3). Both presumably funnel into the same confirmation dialog (§2.11).
- **Implied logic**: editing Amount on an expense that already has payments/splits recorded against it is a state that needs a rule (the design doesn't show this edge case) — see Open Questions (§7).

### 2.4 Add Payment screen
- **Header pattern**: `Cancel` / title / `Save`.
- **Read-only recap card**: `Total Amount` and `Remaining` — shown before any input, so the user always sees the ceiling they're working against.
- **Payment Type toggle**: `Advance` vs `Settle` — a segmented control, mutually exclusive, `Advance` selected by default in this mock.
  - This is the key modeling decision of the whole flow: **a single "Add Payment" screen handles two conceptually different actions** depending on this toggle:
    - *Advance* = a partial/pre-payment that does **not** close the expense, regardless of amount.
    - *Settle* = a payment that (at least intends to) close the expense out.
  - This raises the question of why "Settle Amount" also exists as its own separate screen (2.6) — see §6 for how these two screens likely relate.
- **Amount field**: pre-filled with a value smaller than Remaining (₹600 of ₹1,200) — supports partial entry.
- **Date field**: defaults to *today or a future date* relative to the expense date shown elsewhere (expense dated Jun 18, payment dated Jul 02) — payments are dated independently of the expense's own date.
- **Note field**: optional.
- **Contextual helper text**: "This is an advance payment. You will still see the remaining amount until it's settled." — only relevant/shown when `Advance` is selected; by implication, selecting `Settle` would show different (or no) helper text.

### 2.5 Split Expense screen
- **Header pattern**: `Cancel` / title / `Save`.
- **Read-only `Total Amount`** — the amount being split is fixed at this point (already an existing expense being retroactively split).
- **Split Type toggle**: `Equal` (selected) vs `Custom` — same segmented-control pattern as Payment Type.
- **People list**, each row: avatar, name, computed/entered share amount, checkbox.
  - `You (Paid)` — ₹600, checkbox appears **unchecked/disabled** — the payer's own share is shown but not itself "collectible," consistent with excluding the payer from settlement tracking.
  - `Rahul Sharma` — ₹300, checked.
  - `Priya Mehta` — ₹300, checked.
  - Note the arithmetic: 600 + 300 + 300 = 1,200 = Total. But this is a **3-way split** where "You" gets a disproportionate 600 share (half) while the other two get equal 300 shares each — this is *not* a naive equal 3-way split (which would be 400/400/400). This strongly suggests "Equal" here means **equal among the selected/checked people only**, and "You" holding the checkbox unchecked/reserved is handled as a separate, fixed leftover share — i.e., the split is computed as `(Total − paid-by-you fixed share) / n` over the checked participants, or checking/unchecking a person redistributes the remaining total across whichever people are checked. This checkbox-driven recompute is the core interactive logic of this screen.
- **`+ Add Person`** — extends the split to more participants, presumably triggering a recompute of Equal shares.
- **Summary line**: "You will receive ₹600" — recomputed live from the checked participants' shares (excludes "You"'s own portion, matching the contact ledger's "You will receive" semantics from screen 1).
- **Helper text**: "After splitting, each person will have their own share and you can collect separately." — confirms that splitting an *existing single expense* fans it out into N independently-trackable receivables (each presumably gets its own status/settlement lifecycle going forward, not one shared status for the whole expense anymore).

### 2.6 Settle Amount screen
- **Header pattern**: `Cancel` / title / **`Settle`** (not "Save" — the primary action is explicitly named after the domain action).
- **Read-only recap card**: `Total Amount`, `Paid` (already collected so far), `Remaining` — three-line breakdown, one more line than Add Payment's two-line recap, since Settle needs to show history-to-date.
- **Contextual info banner**: "You are about to mark this expense as fully settled." — always shown, framing the irreversible-ish nature of this action.
- **Payment Date** field (chevron → picker).
- **Note (Optional)** field.
- **Toggle**: "I have received the full amount" — **on by default**. This is the gating control:
  - When ON: the confirmation footer reads "This expense will be marked as **Settled ✓**".
  - Toggling it OFF presumably changes that footer's target status (likely back to `Partial` or blocks the primary action entirely — the mock only shows the ON state). This is the mechanism behind the "Cannot Settle" warning (§2.11): if remaining > 0 and the user tries to force `Settled` without actually having collected the full amount, the toggle/validation blocks it.
- **Live-updating outcome preview**: "This expense will be marked as: `Settled ✓`" — the screen previews the resulting status before commit, not just after.

### 2.7 Expense Updated dialog
- Generic success confirmation pattern: checkmark icon, title, subtitle, then a recap card of the affected expense (name, amount, **current status pill**), then a compact **Actions list** (Add Payment / Split Expense / Settle Amount — notably **not** Edit or Delete, since you just edited/acted on it) offering an immediate next action without leaving the dialog, then `Done` to dismiss.
- Interesting: the recap card's status pill still shows `Pending` in this example — implying this dialog is reused for actions that **don't necessarily change status** (e.g. confirming an Edit that only changed the note/category), not exclusively for payment/settle actions.

### 2.8 Status Indicators (legend)
Four canonical statuses, each a colored pill:
| Status | Color | Meaning (inferred) |
|---|---|---|
| **Pending** | Orange | Nothing collected yet; not past due |
| **Partial** | Yellow/tan | Some amount collected (via Add Payment → Advance), remainder outstanding |
| **Settled ✓** | Green | Fully collected — terminal state |
| **Overdue** | Red/pink | Nothing (or not enough) collected **and** past some due/expected date |

This is a **state machine**, not independent flags — see §4 for the derived transition diagram.

### 2.9 Quick Notes (helper copy)
- Confirms four supported user actions in plain language: track what others owe, add advance payments *anytime* (i.e., not gated to a specific expense state), split among multiple people, settle the full amount.

### 2.10 Tips (helper copy)
- **Long-press** on an expense row is a secondary, faster entry point into "quick actions" (presumably a context menu/bottom sheet with the same Edit/Add Payment/Split/Settle/Delete options as screen 2.2, without a full navigation).

### 2.11 Warning & Confirmation Messages
Four reusable dialogs, all in the same visual family, split by icon/severity, in the order they appear on the canvas:

| Dialog | Icon | Trigger (inferred) | Buttons |
|---|---|---|---|
| **Delete Expense?** | Orange/amber warning | Tapping "Delete Expense" (from 2.2 or 2.3) | `Cancel` / `Delete` (destructive, red) |
| **Unsaved Changes** | Orange/amber warning | Backing out of Edit Expense (2.3) — or any modal form — with dirty fields | `Stay` / `Discard` (destructive) |
| **Partial Payment** | Blue info | After saving an `Advance` payment that doesn't cover the full remaining amount | `OK` (single button, informational only) |
| **Cannot Settle** | Red warning/error | Attempting to Settle (2.6) while `Remaining > 0` and full amount hasn't actually been received | `OK` (single button, blocks the action) |

Note the severity gradient is deliberate: destructive choices get two buttons (an escape hatch), informational/blocking states get one (`OK`) because there's nothing to choose between — you either acknowledge, or (for "Cannot Settle") you're blocked outright and must go fix the input.

### 2.12 Privacy footer
"Your data is safe and private. All changes are stored securely on your device." — implies **local-first / on-device storage** is a user-facing selling point of this feature, worth surfacing prominently (as shown, bottom of the design canvas, likely a persistent footer or onboarding card rather than tied to one specific screen).

---

## 3. End-to-End User Flow

```
Contact Ledger (1)
  │
  ├─ [+ Add Expense] ──────────────────────────────► (new-expense form, not shown in this set)
  │
  └─ [tap a row] ──► Expense Details (2)
                        │
                        ├─ Edit Expense ──► Edit Expense form (3)
                        │                      ├─ Save ──► Expense Updated (7) ──► back to (2)
                        │                      ├─ Delete Expense ──► "Delete Expense?" (11.1)
                        │                      │                        ├─ Cancel ──► stay on (3)
                        │                      │                        └─ Delete ──► back to Contact Ledger (1)
                        │                      └─ back/cancel with dirty fields ──► "Unsaved Changes" (11.2)
                        │                                                              ├─ Stay ──► stay on (3)
                        │                                                              └─ Discard ──► back to (2)
                        │
                        ├─ Add Payment ──► Add Payment form (4)
                        │                     ├─ [Advance] Save, amount < remaining
                        │                     │        ──► "Partial Payment" info (11.3) ──► Expense Updated (7), status → Partial
                        │                     └─ [Settle] Save, amount == remaining
                        │                              ──► Expense Updated (7), status → Settled
                        │
                        ├─ Split Expense ──► Split Expense form (5)
                        │                       └─ Save ──► Expense Updated (7)
                        │                                     (expense now tracked per-participant)
                        │
                        ├─ Settle Amount ──► Settle Amount form (6)
                        │                       ├─ toggle ON, remaining fully covered ──► Settle
                        │                       │        ──► Expense Updated (7), status → Settled ✓
                        │                       └─ attempt Settle while remaining > 0 / toggle off
                        │                                ──► "Cannot Settle" (11.4) ──► stays on (6)
                        │
                        └─ Delete Expense ──► "Delete Expense?" (11.1) ──► same as above
```

Secondary path: **long-press any row on the Contact Ledger (1)** opens the same Edit/Add Payment/Split/Settle/Delete action set as a quick-actions sheet, bypassing the Expense Details screen (2) entirely.

---

## 4. Status State Machine (inferred)

```
                 ┌───────────┐
   (created,     │  PENDING  │
    no payment) ─►           │
                 └─────┬─────┘
                        │ Add Payment (Advance, partial amount)
                        ▼
                 ┌───────────┐
                 │  PARTIAL  │──────┐
                 └─────┬─────┘      │ Add Payment (Advance, more partial amount) — loops on itself
                        │            │
      Settle Amount     │            │
      (full remaining   │            ▼
       received)        │      ┌───────────┐
                        │      │  PARTIAL  │ (unchanged)
                        ▼      └───────────┘
                 ┌───────────┐
                 │ SETTLED ✓ │  (terminal)
                 └───────────┘

   PENDING or PARTIAL + due-date passed with money still owed
                        │
                        ▼
                 ┌───────────┐
                 │  OVERDUE  │  (time-based overlay state, not reachable from Settle)
                 └───────────┘
```

Key rules implied by the design:
1. **PENDING → PARTIAL**: any `Add Payment` (Advance) where the amount collected so far is `> 0` and `< Total Amount`.
2. **PENDING/PARTIAL → SETTLED**: either (a) an `Add Payment` whose cumulative amount reaches the full total, or (b) explicit `Settle Amount` with the "I have received the full amount" toggle on.
3. **SETTLED is terminal** in this design — no screen shows re-opening a settled expense.
4. **OVERDUE** looks like a derived/computed status (date-based), likely `status = Overdue if (Pending or Partial) and dueDate/expenseDate < today`, rather than something explicitly set by user action — it never appears as an option the user picks, only as a legend entry.
5. `Settle Amount` is guarded: it can *fail* (→ "Cannot Settle") if the real remaining balance is greater than zero and the user hasn't actually collected it — meaning the toggle isn't purely cosmetic, it must be validated against `Remaining` at save time, not just trusted at face value.

---

## 5. Business Rules & Calculations (inferred from on-screen numbers)

- **Reconciliation identity** (Contact Ledger header):
  `Total Spent = Total Settled + You will receive (pending)`
  → 6,000 = 3,550 + 2,450 ✓ (holds exactly in the mock, so treat as a hard invariant, not a coincidence.)

- **Per-expense remaining**:
  `Remaining = Total Amount − Paid so far`
  → Screens 4 and 6 both show this pattern (₹1,200 total, ₹600 paid/advanced, ₹600 remaining).

- **Split share allocation** (screen 5):
  Not a naive `Total / participantCount` for every row — "You" holds a fixed/reserved share (₹600) and the *remaining* amount is divided across the checked/selected other participants (₹600 ÷ 2 = ₹300 each under "Equal"). Implies the split algorithm should be:
  `perPersonShare (Equal) = (Total − sum of unchecked/reserved shares) / count(checked participants)`
  and "Custom" presumably lets each row's amount be typed in directly, with a running total that must reconcile back to `Total Amount` before Save is enabled (not shown, but the standard pattern for this UI).

- **"You will receive" after split** = sum of shares assigned to *other* people only (excludes "You (Paid)"'s own ₹600) — consistent with the Contact Ledger's top-level metric of the same name.

- **Advance vs Settle semantics** (screen 4's toggle) functionally overlaps with the dedicated Settle Amount screen (6). The most coherent read: **Add Payment** is the general-purpose "record money received" action for *any* amount (its `Settle` option is a shortcut equivalent to typing the full remaining amount), while **Settle Amount** (screen 6) is a *dedicated, more ceremonious* flow specifically for the "close this out" moment — it shows fuller payment history context (`Paid` line) and an explicit confirmation toggle/banner that Add Payment's Settle mode doesn't show. Both funnel through the same underlying "record a payment, recompute status" logic.

- **Deletion cascade**: deleting an Expense also deletes "all related payments" per the persistent warning on screen 2 — so any Add Payment / Settle Amount records tied to that expense must cascade-delete together, and this must be communicated as irreversible ("cannot be undone").

---

## 6. Design Ambiguities Worth Resolving Before Implementation

1. **Add Payment vs Settle Amount overlap** — Add Payment's "Settle" toggle option seems to duplicate the dedicated Settle Amount screen's job. Decide whether Settle Amount is (a) a genuinely separate flow reachable only when `Remaining == amount entered`, or (b) Add Payment's "Settle" mode should simply deep-link into screen 6 instead of being a third path to the same outcome.
2. **Split screen's "You (Paid)" checkbox** — shown checked-off/disabled but it's unclear whether unchecking it (i.e., "I didn't actually pay any of this myself") is a supported interaction, or whether the checkbox there is purely decorative/status-only (vs. the other two rows' checkboxes, which look like real toggles controlling who's included in the Equal split).
3. **Editing an expense that already has payments or a split** — screen 3 (Edit Expense) shows only simple fields (Title/Amount/Date/Category/Note) with no participant list, and no visible guard for "you're reducing Amount below what's already been paid." Needs a rule: block, warn, or auto-adjust remaining/participant shares.
4. **What triggers Overdue** — no due-date field appears anywhere in Add Expense/Edit Expense; Overdue must be derived from the expense's own date (e.g., `N` days after `date` with no settlement) rather than a user-set due date, unless a due-date field exists on the (unseen) Add Expense screen.
5. **Summary and Payments tabs** (screen 1) — their content isn't shown in this frame set; only History is detailed. Needs its own spec before implementation.
6. **Splitting an already-partially-paid expense** — if ₹600 of ₹1,200 has already been received before the user opens Split Expense, it's unclear whether the already-collected ₹600 is attributed to a specific person or held against the total before per-person shares are computed.

---

## 7. Summary

The design describes a **per-contact expense ledger** where each expense carries an independent 4-state lifecycle (`Pending → Partial → Settled`, with `Overdue` as a time-derived overlay), driven by two payment-recording surfaces (a general `Add Payment` with Advance/Settle modes, and a dedicated `Settle Amount` closer) plus a retroactive `Split Expense` action that fans a single expense into multiple trackable per-person shares. Every mutating action is backstopped by a small, consistent set of guardrail dialogs (destructive confirm, unsaved-changes confirm, informational partial-payment ack, and a hard block on settling short of the full amount), and the numbers on screen 1 confirm a strict accounting identity (`Spent = Settled + Pending`) that any implementation must preserve exactly.
