# UI/UX Design System — Premium Fintech Redesign Playbook

Reference for redesigning any screen in this app to the "premium fintech"
bar (Revolut / Monzo / CRED / Apple Wallet). Written from the **Add Credit
Card** wizard rebuild (`lib/features/credit_cards/presentation/widgets/credit_card_form_sheet.dart`)
— treat that file as the canonical example alongside this doc.

## 1. Design philosophy

- **UX before aesthetics.** A screen isn't done because it looks good — it's
  done because the golden path takes the fewest, clearest decisions. Visual
  polish is the last 10%, not the first.
- **Guided over exposed.** Long forms become multi-step wizards, not longer
  scrolls. Each step asks one coherent question ("who's this card from and
  what's it called", "how much can you spend", "when's it due"), never a
  grab-bag of unrelated fields.
- **Information density without clutter.** Group related fields into a
  single elevated card instead of scattering labeled `TextFormField`s
  directly on the background. Fewer, denser cards read calmer than many
  thin rows.
- **Never touch business logic for a visual pass.** A redesign changes the
  widget tree, not the state machine, validators, or repository calls. If a
  test asserts on a specific interaction (tap a dropdown, read a computed
  label), the redesign must preserve that interaction's *outcome*, updating
  the test only for interaction *mechanics* that intentionally changed
  (e.g., dropdown → chip picker).

## 2. Structure: when to wizardize

Convert a long single-scroll form into a step wizard when:
- It has 4+ logically distinct groups of fields (identity, money, dates,
  extras — the natural chunks users think in), **and**
- Fields in one group don't need to see live values from a later group to
  validate (if step 2 depends on step 4's answer, don't split them apart).

Keep a single scroll (just re-skinned) when:
- The form is short enough to see most of it without scrolling on a small
  phone, or
- Steps would have no independent identity (e.g., "misc settings" is not a
  step, it's a section).

Wizard shell contract:
- Full-screen route (`MaterialPageRoute(fullscreenDialog: true)`), not a
  bottom sheet — steps need the vertical room a sheet doesn't have.
- Segmented top progress bar (filled pill segments, not dots) showing
  `currentStep / stepCount`.
- Back arrow steps backward through the wizard before it ever pops the
  route (`PopScope` + `canPop: step == 0`).
- One persistent bottom CTA: `Continue` on every step except the last,
  which reads as the terminal action (`Add card`, `Save changes`, etc.).
- `PageView` + `NeverScrollableScrollPhysics`, moved only by `Continue`/back
  — never let the user swipe past unvalidated fields.

## 3. Component vocabulary

Reusable pieces built for this pass — reuse these names/shapes for the next
screen rather than inventing new ones:

| Component | Purpose | Key traits |
|---|---|---|
| `_StepHeader` | Per-step title block | Numbered circle badge + bold title + one-line subtitle |
| `_StepProgressBar` | Top-of-wizard progress | Segmented pill row, animated fill |
| `_SectionCard` | Group related fields | Soft shadow (`AppShadows.soft`), `AppSizes.radiusCard`, faint outline border |
| `_PremiumField` | Text input | Filled, borderless until focus, `AppSizes.radiusMd`, no visible border by default |
| `_PremiumDropdown<T>` | Select input | Same filled look as `_PremiumField` so pickers don't break field rhythm |
| Chip-style selector (e.g. `_NetworkChip`) | Small closed set of mutually exclusive options (≤5) | Tap-to-select chip grid beats a dropdown when every option is short and worth seeing at a glance |

Rule of thumb: **dropdown for open-ended/long lists, chips for a handful of
short mutually-exclusive options.** A network picker with 4 entries is a
chip grid; a bank picker with 50+ entries stays a searchable sheet.

## 4. Visual language

- **8pt grid.** All spacing pulls from `AppSizes` (`xs=4, sm=8, md=12,
  lg=16, xl=24, xxl=32`). Never hardcode a pixel value that isn't one of
  these.
- **Radius hierarchy.** `radiusMd` (16) for inputs/buttons, `radiusLg` (22)
  for hero visuals (card preview), `radiusCard` (24) for section panels,
  `radiusPill` for progress bars/chips.
- **Soft elevation, not Material default elevation.** Use `AppShadows.soft`
  (a single soft `BoxShadow`, theme-aware alpha) on hero elements and
  section cards instead of `Card`'s harsh default elevation.
- **Typography weight over size for hierarchy.** Prefer bumping
  `FontWeight` (600–800) over jumping a whole type scale step — keeps
  density high while still reading as clearly hierarchical.
- **Color restraint.** One primary accent color drives selection state
  (borders, check icons, progress fill). Card face colors are the one place
  a broader palette is intentional (the product itself is about bank
  cards).

## 5. Interaction & motion

- Selection state changes (color swatch, network chip, step transition) get
  a short `AnimatedContainer`/`PageView.animateToPage` transition
  (150–260ms, `Curves.easeOutCubic`) — never an instant snap, never a
  multi-second delay.
- Live preview: whenever a form is building a visual object (a card, in
  this case), show it updating in real time as fields are filled, at the
  top of the *first* relevant step and again at the point where its
  appearance is being tuned (color/step 4). Don't make the user imagine the
  result.
- Every async save button gets a built-in loading spinner state
  (`PrimaryButton(isLoading: ...)`) — never a bare disabled button with no
  feedback.

## 6. Testing implications (read before redesigning a tested screen)

- **`ListView` lazily builds only the viewport** — a `flutter_test` canvas
  is small (≈800×600 by default), so fields below the fold in a `ListView`
  simply don't exist in the widget tree yet, and `find.text(...)` will
  report 0 matches even though the widget "looks right" in a real device
  screenshot. Use `SingleChildScrollView(child: Column(...))` for
  step/page content so widget tests (and `ensureVisible`) can reach
  everything eagerly, exactly like the original single-scroll form did.
- When a redesign changes *how* an option is selected (dropdown → chip,
  sheet → inline picker), update the existing test's tap sequence to match
  the new mechanic, but keep asserting the same computed outcome (e.g., the
  "Shown as ..." computed name preview). Never delete the assertion just
  because the interaction changed.
- Run the full feature's test folder after a redesign, not just the one
  file you touched — nested Scaffold/Navigator changes can silently affect
  sibling screens that push this one as a route.

## 7. Checklist for the next screen

1. Does this screen have 4+ distinct field groups? → wizard candidate.
2. List every existing controller/provider/validator call — the redesign
   must reference every single one; nothing gets dropped silently.
3. Pick component vocabulary from §3 before inventing new widgets.
4. Build with `SingleChildScrollView`, not `ListView`, per step.
5. Re-run `flutter analyze` + the feature's full test folder before calling
   it done — not just the file you edited.
6. [[verify-ui-on-small-android-layout]] — check on a small phone for
   wrapping/overflow/alignment before considering the task complete.
