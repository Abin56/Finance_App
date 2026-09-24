import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/month_year_stepper.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/domain/credit_card_profile.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../expense/data/expense_repository.dart';
import '../../../expense/domain/expense.dart';
import '../../../expense/domain/split_type.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../expense/presentation/widgets/add_expense_chooser.dart';
import '../../../expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../../people/presentation/widgets/person_picker_sheet.dart';
import '../../../sms_inbox/domain/merchant/merchant_category_suggester.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
import '../../../sms_inbox/presentation/widgets/sms_suggestion_hint.dart';
import '../../domain/transaction.dart';
import '../../domain/transaction_type.dart';
import '../providers/transaction_providers.dart';

/// Full-screen replacement for the old `TransactionFormSheet` bottom sheet,
/// matching the "Add Expense" Figma mockup: Description/Notes up top, a
/// tap-to-pick Category row, combined Date & Time, and Payment Method chips
/// (backed by the existing [Account] list) instead of dropdowns.
/// Switching the Expense/Income/Transfer segment re-filters the category
/// picker to only categories applicable to the selected type, clearing the
/// selection if it no longer applies. The "Split Expense" row offers to
/// close this screen and open [SplitExpenseFormSheet] instead — the
/// existing split engine, not a second implementation of it.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({
    super.key,
    this.transaction,
    this.smsPrefill,
    this.initialType,
  });

  final Transaction? transaction;

  /// Set when this screen was opened from the SMS Inbox's convert sheet —
  /// seeds the amount/description/date/account/category fields as normal,
  /// fully editable initial values (never locked/read-only, since a parsed
  /// SMS is a best guess). On successful save, the linked SMS row is marked
  /// imported. Mutually exclusive with [transaction] (SMS conversion always
  /// creates a brand-new transaction, never edits an existing one).
  final SmsPrefill? smsPrefill;

  /// Which segment to start on when creating from an [smsPrefill] — "My
  /// Income" opens on [TransactionType.income], every other SMS target that
  /// reuses this screen (My Expense, Credit Card Purchase) leaves the
  /// default [TransactionType.expense].
  final TransactionType? initialType;

  static Future<void> show(
    BuildContext context, {
    Transaction? transaction,
    SmsPrefill? smsPrefill,
    TransactionType? initialType,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          transaction: transaction,
          smsPrefill: smsPrefill,
          initialType: initialType,
        ),
      ),
    );
  }

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: widget.transaction != null
        ? widget.transaction!.amount.toStringAsFixed(2)
        : (widget.smsPrefill == null
              ? ''
              : widget.smsPrefill!.amount.toStringAsFixed(2)),
  );
  late final _descriptionController = TextEditingController(
    text:
        widget.transaction?.description ??
        widget.smsPrefill?.merchantOrSender ??
        '',
  );
  final _descriptionFocusNode = FocusNode();
  late final _notesController = TextEditingController(
    text: widget.transaction?.notes ?? widget.smsPrefill?.note ?? '',
  );
  late TransactionType _type =
      widget.transaction?.type ?? widget.initialType ?? TransactionType.expense;
  late DateTime _dateTime =
      widget.transaction?.dateTime ??
      widget.smsPrefill?.dateTime ??
      DateTime.now();
  late String? _accountId =
      widget.transaction?.accountId ?? widget.smsPrefill?.suggestedAccountId;
  late String? _categoryId =
      widget.transaction?.categoryId ?? widget.smsPrefill?.suggestedCategoryId;
  late bool _excludeFromCalculations =
      widget.transaction?.excludeFromCalculations ?? false;
  late String? _linkedPersonId = widget.transaction?.linkedPersonId;

  /// Whether [_linkedPersonId] represents money owed back — starts matching
  /// the transaction's own flag when editing (see [Transaction.owesPersonToggle]),
  /// always false for a brand-new transaction until the user opts in.
  late bool _owesPersonToggle = widget.transaction?.owesPersonToggle ?? false;

  /// The original toggle state at load time, so `_save` can tell whether the
  /// owed relationship needs to be created/reversed/reassigned rather than
  /// just re-saved in place.
  late final bool _initialOwesPersonToggle = _owesPersonToggle;
  late final String? _initialLinkedPersonId = _linkedPersonId;

  /// Whether the "Move to another month" branch is active — starts true
  /// only when editing a transaction that already has one set.
  late bool _customAccountingMonth =
      widget.transaction?.accountingMonth != null;
  late DateTime _accountingMonth =
      widget.transaction?.accountingMonth ??
      DateTime(_dateTime.year, _dateTime.month);
  bool _isSaving = false;
  String? _accountError;
  String? _categoryError;

  /// Presentation-only progressive-disclosure state (not persisted): Notes
  /// and Advanced Options stay collapsed on a fresh form so the fast path
  /// (Amount → Description → Category → Payment → Save) has nothing extra
  /// to scroll past, but start open when editing a transaction that already
  /// has a note or a non-default advanced setting, so nothing is hidden.
  late bool _notesExpanded =
      (widget.transaction?.notes ?? widget.smsPrefill?.note ?? '')
          .isNotEmpty;
  late bool _advancedExpanded =
      (widget.transaction?.excludeFromCalculations ?? false) ||
      widget.transaction?.accountingMonth != null;

  /// The suggestion hint's source, but only while the suggested category is
  /// still the one selected. The moment the user picks something else the
  /// hint disappears, because it would then be describing a category that is
  /// no longer there — and it must never look like the app is arguing with a
  /// choice the user just made.
  SuggestionSource? get _activeCategorySuggestion {
    final prefill = widget.smsPrefill;
    if (prefill?.suggestedCategoryId == null) return null;
    if (_categoryId != prefill!.suggestedCategoryId) return null;
    return prefill.categorySuggestionSource;
  }

  bool get _isEditing => widget.transaction != null;

  DateTime get _accountingMonthBounds => DateTime.now();

  /// "Today"/"Yesterday" for the common case, falling back to the full date
  /// — purely a display label, [_dateTime] itself is unaffected.
  String get _dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(_dateTime.year, _dateTime.month, _dateTime.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return _dateTime.fullDate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dateTime.hour,
        _dateTime.minute,
      );
      // Keep the default ("Same as Transaction Date") in sync with the new
      // date — only meaningful while the user hasn't opted into a custom
      // Accounting Month.
      if (!_customAccountingMonth) {
        _accountingMonth = DateTime(_dateTime.year, _dateTime.month);
      }
    });
  }

  Future<void> _pickPerson() async {
    final picked = await showPersonPickerSheet(context);
    if (picked == null) return;
    setState(() => _linkedPersonId = picked.id);
  }

  void _clearPerson() {
    setState(() {
      _linkedPersonId = null;
      _owesPersonToggle = false;
    });
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _CategoryPickerSheet(categories: categories, selectedId: _categoryId),
    );
    if (picked == null) return;
    setState(() {
      _categoryId = picked;
      _categoryError = null;
      if (_descriptionController.text.trim().isEmpty) {
        final category = categories.where((c) => c.id == picked).firstOrNull;
        if (category != null) _descriptionController.text = category.name;
      }
    });
  }

  /// Carries every field already typed on this still-live form over into
  /// [SplitExpenseFormSheet], so switching flows never re-asks for the same
  /// information.
  AddExpenseDraftPrefill _buildDraftPrefill() => AddExpenseDraftPrefill(
    amount: double.tryParse(_amountController.text.trim()),
    description: _descriptionController.text.trim(),
    categoryId: _categoryId,
    accountId: _accountId,
    date: _dateTime,
    notes: _notesController.text.trim(),
    excludeFromCalculations: _excludeFromCalculations,
    accountingMonth: _customAccountingMonth ? _accountingMonth : null,
  );

  /// Opens [SplitExpenseFormSheet] directly on top of this still-live screen
  /// — same "Add Expense" entry point, just routed to the multi-person split
  /// engine instead of a plain transaction, with no logic duplicated here.
  /// Deliberately skips [AddExpenseChooser]'s split-vs-assign choice: singly
  /// assigning a brand-new expense to one person (with a real ledger effect)
  /// isn't offered from this screen at all — "Person (optional)" already
  /// covers the lightweight "tag a person" case, and [AddExpenseChooser]'s
  /// "This person will pay" option stays reachable from the Contact Ledger
  /// screen, where it's the more natural default. Deliberately does NOT pop
  /// this screen first: if the user backs out of the sheet without saving,
  /// they land right back on this form with every field intact. Only a
  /// genuine save closes this screen too, so they don't end up stuck on a
  /// stale empty form after the shared expense already went through.
  Future<void> _switchToSplitExpense(BuildContext context) async {
    final saved = await SplitExpenseFormSheet.show(
      context,
      draft: _buildDraftPrefill(),
    );
    if (saved == true && context.mounted) Navigator.of(context).pop();
  }

  /// Whether this save should end up "owed" — the toggle only ever applies
  /// to an expense with a linked person; switching type away from Expense or
  /// clearing the person always forces it back off, so an edit can never
  /// leave a stray owed [Expense] behind a non-expense/unlinked transaction.
  bool get _effectiveOwesToggle =>
      _owesPersonToggle &&
      _linkedPersonId != null &&
      _type == TransactionType.expense;

  /// Reverses [transaction]'s backing [Expense] (the person originally
  /// linked before this edit) via [ExpenseRepository.unassignFromPerson] —
  /// the ledger/schedule reversal, leaving [transaction] itself alone. A
  /// no-op if no [Expense] exists (defensive: `wasOwed` should already
  /// guarantee one does).
  Future<void> _unassignExisting(Transaction transaction) async {
    final expense = ref.read(expenseForTransactionProvider(transaction.id));
    if (expense == null) return;
    await ref.read(expenseRepositoryProvider).unassignFromPerson(expense);
  }

  /// Hands [transaction] over to [ExpenseRepository.convertToAssigned] so a
  /// real single-participant [Expense]/ledger entry backs it — same engine
  /// [AssignExpenseSheet] already uses, just triggered from this screen's
  /// toggle instead of a separate sheet. Reuses whatever [Expense] document
  /// may already exist for [transaction] (there shouldn't be one on a fresh
  /// reference-only transaction, but `convertToAssigned` handles either way,
  /// same as [TransactionDetailScreen]'s own "Assign to person" action).
  Future<void> _convertExistingToOwed(
    Transaction transaction,
    String description,
  ) async {
    final people = ref.read(peopleStreamProvider).value ?? const [];
    final person = people.where((p) => p.id == _linkedPersonId).firstOrNull;
    final existingExpense = ref.read(
      expenseForTransactionProvider(transaction.id),
    );
    final expenseRepository = ref.read(expenseRepositoryProvider);
    await expenseRepository.convertToAssigned(
      existingExpense: existingExpense,
      transactionId: transaction.id,
      description: description.isNotEmpty ? description : 'Expense',
      totalAmount: double.parse(_amountController.text.trim()),
      date: _dateTime,
      categoryId: _categoryId!,
      accountId: _accountId!,
      notes: _notesController.text.trim(),
      personId: _linkedPersonId!,
      personName: person?.name ?? '',
    );
    final repository = ref.read(transactionRepositoryProvider);
    await repository.editTransaction(
      transaction,
      linkedPersonId: _linkedPersonId,
      owesPersonToggle: true,
    );
  }

  /// Still owed, same person — edits the existing backing [Expense] in place
  /// via [ExpenseRepository.editExpense] (which itself keeps the linked
  /// [Transaction] in sync), so the person's ledger history line updates
  /// instead of being reversed and recreated.
  Future<void> _editExistingOwed(
    Transaction transaction,
    String description,
  ) async {
    final expense = ref.read(expenseForTransactionProvider(transaction.id));
    if (expense == null) {
      // Defensive fallback: `wasOwed` implied an Expense should exist; if it
      // was deleted out from under this edit, treat it like a fresh assign.
      await _convertExistingToOwed(transaction, description);
      return;
    }
    final totalAmount = double.parse(_amountController.text.trim());
    final currentInstallments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.read(installmentsStreamProvider(expense.scheduleId!)).value ??
              const <Installment>[];
    await ref
        .read(expenseRepositoryProvider)
        .editExpense(
          expense: expense,
          currentInstallments: currentInstallments,
          description: description.isNotEmpty ? description : 'Expense',
          totalAmount: totalAmount,
          date: _dateTime,
          categoryId: _categoryId,
          accountId: _accountId,
          notes: _notesController.text.trim(),
          splitType: SplitType.custom,
          participantInputs: [
            for (final p in expense.participants)
              ExpenseParticipantInput(
                personId: p.personId,
                name: p.name,
                isMe: p.isMe,
                value: p.isMe ? 0 : totalAmount,
              ),
          ],
        );
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState!.validate();
    setState(() {
      _accountError = _accountId == null ? 'Select a payment method' : null;
      _categoryError = _categoryId == null ? 'Select a category' : null;
    });
    if (!formValid || _accountId == null || _categoryId == null) return;

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(transactionRepositoryProvider);
      final amount = double.parse(_amountController.text.trim());
      final descriptionInput = _descriptionController.text.trim();
      final categories = ref.read(categoriesForTypeProvider(_type));
      final description = descriptionInput.isNotEmpty
          ? descriptionInput
          : categories.where((c) => c.id == _categoryId).firstOrNull?.name ??
                (_type == TransactionType.income ? 'Income' : 'Expense');

      final accountingMonth = _customAccountingMonth ? _accountingMonth : null;

      if (_isEditing) {
        final wasOwed =
            _initialOwesPersonToggle && _initialLinkedPersonId != null;
        final nowOwed = _effectiveOwesToggle;
        final transaction = widget.transaction!;

        if (wasOwed && !nowOwed) {
          // Owed -> reference-only (or person cleared entirely): reverse the
          // ledger/schedule via the same repository that created it, then
          // save this as a plain transaction with whatever linkedPersonId is
          // left (null if the person was cleared, unchanged if only the
          // toggle was switched off).
          await _unassignExisting(transaction);
          await repository.editTransaction(
            transaction,
            type: _type,
            amount: amount,
            dateTime: _dateTime,
            accountId: _accountId,
            categoryId: _categoryId,
            description: description,
            notes: _notesController.text.trim(),
            excludeFromCalculations: _excludeFromCalculations,
            accountingMonth: accountingMonth,
            clearAccountingMonth: accountingMonth == null,
            linkedPersonId: _linkedPersonId,
            clearLinkedPersonId: _linkedPersonId == null,
            owesPersonToggle: false,
          );
        } else if (!wasOwed && nowOwed) {
          // Reference-only (or brand plain) -> owed: hand this transaction
          // over to ExpenseRepository so a real Expense/ledger entry backs
          // it, same mechanism AssignExpenseSheet already uses.
          await _convertExistingToOwed(transaction, description);
        } else if (wasOwed && nowOwed) {
          if (_initialLinkedPersonId != _linkedPersonId) {
            // Person changed while staying owed: reverse the old person's
            // ledger entry, then re-assign to the new person — two existing
            // calls, no new ledger math.
            await _unassignExisting(transaction);
            await _convertExistingToOwed(transaction, description);
          } else {
            // Still owed, same person — edit the backing Expense in place so
            // the same ledger/installment history line updates instead of
            // being reversed and recreated.
            await _editExistingOwed(transaction, description);
          }
        } else {
          // Was never owed, still isn't — the plain path, unchanged.
          await repository.editTransaction(
            transaction,
            type: _type,
            amount: amount,
            dateTime: _dateTime,
            accountId: _accountId,
            categoryId: _categoryId,
            description: description,
            notes: _notesController.text.trim(),
            excludeFromCalculations: _excludeFromCalculations,
            accountingMonth: accountingMonth,
            clearAccountingMonth: accountingMonth == null,
            linkedPersonId: _linkedPersonId,
            clearLinkedPersonId: _linkedPersonId == null,
            owesPersonToggle: false,
          );
        }
      } else {
        // A brand-new expense's linked person is always a plain reference
        // (see the "Add a person (optional)" row's own doc comment) — the
        // owed-toggle state machine above only ever applies to editing an
        // already-owed transaction, so create always takes this plain path.
        final created = await repository.createTransaction(
          type: _type,
          amount: amount,
          dateTime: _dateTime,
          accountId: _accountId!,
          categoryId: _categoryId!,
          description: description,
          notes: _notesController.text.trim(),
          excludeFromCalculations: _excludeFromCalculations,
          accountingMonth: accountingMonth,
          linkedPersonId: _linkedPersonId,
          source: widget.smsPrefill == null ? null : 'sms',
        );

        // Learn from the category the user actually settled on — which may
        // differ from the one suggested — so the next SMS from this
        // merchant starts where they left off. Only ever reached from an
        // SMS conversion, so a plain manual entry records nothing. Any
        // failure in linking/learning is swallowed inside this helper — the
        // transaction above already saved, so it must never be reported as
        // a save failure (see `completeSmsImport`).
        await completeSmsImport(
          ref,
          smsPrefill: widget.smsPrefill,
          linkedEntityId: created.id,
          learnCategoryType: _type,
          learnCategoryId: _categoryId,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save expense: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesForTypeProvider(_type));
    final selectedCategory = categories
        .where((c) => c.id == _categoryId)
        .firstOrNull;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Expense' : 'Add Expense')),
      // The scroll and the pinned save bar are siblings in one Column rather
      // than the save button living at the bottom of the scroll — a
      // persistent CTA doesn't require scrolling to find on this form's
      // busiest state, and Scaffold's default resize-to-avoid-keyboard
      // behavior keeps it pinned above the keyboard for free. There is only
      // one Save affordance (this bar) — the old AppBar text button was a
      // redundant second CTA for the same action.
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  AppSizes.sm,
                  AppSizes.md,
                  AppSizes.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Hero: type + amount + description -------------
                    // A dark "hero surface" card — the same identity the
                    // dashboard's balance card uses (near-black in both
                    // themes) — so the single most important field on the
                    // screen reads as a distinct, premium focal point
                    // instead of sitting on the plain
                    // background like every other field.
                    _HeroCard(
                      child: Column(
                        children: [
                          _TypeToggle(
                            value: _type,
                            onChanged: (type) {
                              setState(() {
                                _type = type;
                                if (_categoryId != null &&
                                    !categories.any(
                                      (c) => c.id == _categoryId,
                                    )) {
                                  _categoryId = null;
                                }
                                if (_type == TransactionType.income) {
                                  final accounts =
                                      accountsAsync.value ?? const [];
                                  final selectedAccount = accounts
                                      .where((a) => a.id == _accountId)
                                      .firstOrNull;
                                  if (selectedAccount != null &&
                                      selectedAccount.type ==
                                          AccountType.card) {
                                    _accountId = null;
                                  }
                                }
                              });
                            },
                          ),
                          const SizedBox(height: AppSizes.sm),
                          // Currency symbol + digits share the same white
                          // hue family (the symbol just dimmer) so "₹ 999"
                          // reads as one connected amount rather than two
                          // differently-colored pieces of text.
                          TextFormField(
                            controller: _amountController,
                            autofocus: !_isEditing,
                            textAlign: TextAlign.center,
                            style: context.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _Hero.onSurface,
                            ),
                            decoration: InputDecoration(
                              // Explicitly unfilled/transparent — without
                              // this the field falls back to the app's
                              // global `inputDecorationTheme.fillColor` (a
                              // near-white box in light mode), painting a
                              // light rectangle inside this dark hero card
                              // and making the white/lime text unreadable
                              // against it. The field must sit directly on
                              // the hero card's own dark surface.
                              filled: true,
                              fillColor: Colors.transparent,
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              errorStyle: TextStyle(color: colors.error),
                              hintText: '0',
                              hintStyle: context.textTheme.headlineLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _Hero.onSurfaceMuted,
                                  ),
                              prefixText: '₹ ',
                              prefixStyle: context.textTheme.headlineLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _Hero.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: Validators.amount,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _descriptionFocusNode.requestFocus(),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          Divider(
                            height: 1,
                            color: _Hero.onSurfaceMuted
                                .withValues(alpha: 0.16),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          TextFormField(
                            controller: _descriptionController,
                            focusNode: _descriptionFocusNode,
                            style: TextStyle(
                              color: _Hero.onSurface,
                            ),
                            cursorColor: _Hero.accent,
                            decoration:
                                _heroFieldDecoration(
                                  context,
                                  prefixIcon: selectedCategory == null
                                      ? null
                                      : Padding(
                                          padding: const EdgeInsets.all(
                                            AppSizes.sm,
                                          ),
                                          child: CircleAvatar(
                                            radius: 11,
                                            backgroundColor: Color(
                                              selectedCategory.colorValue,
                                            ).withValues(alpha: 0.22),
                                            child: Icon(
                                              selectedCategory.icon,
                                              color: Color(
                                                selectedCategory.colorValue,
                                              ),
                                              size: AppSizes.iconSm,
                                            ),
                                          ),
                                        ),
                                  suffixIcon:
                                      _descriptionController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: Icon(
                                            Icons.cancel,
                                            size: AppSizes.iconSm,
                                            color: _Hero.onSurfaceMuted,
                                          ),
                                          onPressed: () => setState(
                                            _descriptionController.clear,
                                          ),
                                        ),
                                ).copyWith(
                                  hintText: 'What did you spend on?',
                                  hintStyle: TextStyle(
                                    color: _Hero.onSurfaceMuted,
                                  ),
                                  counterText: '',
                                ),
                            maxLength: 100,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.lg),

                    // --- Details: category, date, payment, share -------
                    // No single bordered box holding all four fields
                    // anymore — Category/Date are their own compact tiles,
                    // Payment Method chips are already individually
                    // selectable surfaces, and Share Expense gets the same
                    // tile language, so grouping comes from the section
                    // label + consistent spacing/radius instead of one flat
                    // panel with horizontal rule lines inside it (which read
                    // as generic-form, not as this app's premium hero
                    // language).
                    const SectionLabel('Transaction Details'),
                    const SizedBox(height: AppSizes.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _AttributeTile(
                            icon: selectedCategory == null
                                ? Icons.category_outlined
                                : selectedCategory.icon,
                            iconTint: selectedCategory == null
                                ? null
                                : Color(selectedCategory.colorValue),
                            label: 'Category',
                            value:
                                selectedCategory?.name ?? 'Select a category',
                            filled: selectedCategory != null,
                            onTap: () => _pickCategory(categories),
                            errorText: _categoryError,
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: _AttributeTile(
                            icon: Icons.calendar_today_outlined,
                            label: 'Date',
                            value: _dateLabel,
                            filled: true,
                            onTap: _pickDate,
                          ),
                        ),
                      ],
                    ),
                    if (_activeCategorySuggestion case final source?)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSizes.xs),
                        child: SmsSuggestionHint(
                          source: source,
                          merchant: widget.smsPrefill?.merchantOrSender,
                        ),
                      ),
                    const SizedBox(height: AppSizes.md),
                    _requiredLabel(context, 'Payment method'),
                    const SizedBox(height: AppSizes.xs),
                    accountsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) =>
                          Text('Could not load payment methods: $error'),
                      data: (accounts) {
                        final eligibleAccounts =
                            _type == TransactionType.income
                            ? accounts
                                  .where(
                                    (account) =>
                                        account.type != AccountType.card,
                                  )
                                  .toList()
                            : accounts;
                        return Wrap(
                          spacing: AppSizes.sm,
                          runSpacing: AppSizes.sm,
                          children: [
                            for (final account in eligibleAccounts)
                              _PaymentMethodChip(
                                account: account,
                                creditCards: creditCards,
                                selected: account.id == _accountId,
                                onTap: () => setState(() {
                                  _accountId = account.id;
                                  _accountError = null;
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_accountError != null) ...[
                      const SizedBox(height: AppSizes.xs),
                      Text(
                        _accountError!,
                        style: TextStyle(color: colors.error, fontSize: 12),
                      ),
                    ],
                    if (!_isEditing && _type == TransactionType.expense) ...[
                      const SizedBox(height: AppSizes.sm),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusLg,
                          ),
                          border: Border.all(color: colors.outline),
                        ),
                        child: _TapRow(
                          label: null,
                          onTap: () => _switchToSplitExpense(context),
                          leadingIcon: Icons.people_outline_rounded,
                          value: 'Share Expense',
                          valueEmphasis: true,
                          subtitle: 'Share this expense with others',
                          horizontalPadding: AppSizes.md,
                        ),
                      ),
                    ],

                    if (_type == TransactionType.expense) ...[
                      const SizedBox(height: AppSizes.sm),
                      _DetailsCard(
                        children: [
                          _PersonField(
                            personId: _linkedPersonId,
                            onTap: _pickPerson,
                            onClear: _clearPerson,
                          ),
                          // "This person owes me this expense" only edits an
                          // *existing* transaction's owed status — on a
                          // brand-new expense it would just be a second way
                          // to reach `assignToPerson`, duplicating "Share
                          // Expense" -> "This person will pay" above. So a
                          // freshly linked person here always stays a plain
                          // reference (no ledger/balance effect) until the
                          // user picks a real split/assign flow instead.
                          if (_isEditing && _linkedPersonId != null) ...[
                            const _RowDivider(),
                            Material(
                              type: MaterialType.transparency,
                              child: SwitchListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'This person owes me this expense',
                                ),
                                subtitle: const Text(
                                  "Adds this amount to what they owe you, so it shows up when you check their balance later.",
                                ),
                                value: _owesPersonToggle,
                                onChanged: (value) =>
                                    setState(() => _owesPersonToggle = value),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    const SizedBox(height: AppSizes.sm),
                    // --- Notes: secondary, collapsed by default --------
                    _CollapsibleRow(
                      expanded: _notesExpanded,
                      collapsedIcon: Icons.add_rounded,
                      collapsedLabel: 'Add note',
                      expandedLabel: 'Notes',
                      onToggle: () =>
                          setState(() => _notesExpanded = !_notesExpanded),
                      child: TextFormField(
                        controller: _notesController,
                        decoration: _premiumDecoration(context).copyWith(
                          hintText: 'Add a note…',
                        ),
                        minLines: 2,
                        maxLines: 4,
                        textInputAction: TextInputAction.done,
                      ),
                    ),

                    const SizedBox(height: AppSizes.sm),
                    // --- Advanced options: collapsed by default --------
                    _CollapsibleRow(
                      expanded: _advancedExpanded,
                      collapsedIcon: Icons.tune_rounded,
                      collapsedLabel: 'Advanced options',
                      expandedLabel: 'Advanced options',
                      onToggle: () => setState(
                        () => _advancedExpanded = !_advancedExpanded,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                "Don't count this in my totals",
                              ),
                              subtitle: const Text(
                                "Still shows in your history — just won't affect your balance, budgets, or reports.",
                              ),
                              value: _excludeFromCalculations,
                              onChanged: (value) => setState(
                                () => _excludeFromCalculations = value,
                              ),
                            ),
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Count this in a different month?',
                              ),
                              subtitle: Text(
                                _customAccountingMonth
                                    ? 'Choose which month it should count toward below.'
                                    : 'Right now: counted in ${_dateTime.monthYear} (same as the date above)',
                              ),
                              value: _customAccountingMonth,
                              onChanged: (value) => setState(() {
                                _customAccountingMonth = value;
                                if (!value) {
                                  _accountingMonth = DateTime(
                                    _dateTime.year,
                                    _dateTime.month,
                                  );
                                }
                              }),
                            ),
                          ),
                          if (_customAccountingMonth) ...[
                            const SizedBox(height: AppSizes.sm),
                            Text(
                              'Which month should this count toward?',
                              style: context.textTheme.labelLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSizes.xs),
                            MonthYearStepper(
                              value: _accountingMonth,
                              min: DateTime(
                                _accountingMonthBounds.year - 5,
                                _accountingMonthBounds.month,
                              ),
                              max: DateTime(
                                _accountingMonthBounds.year + 2,
                                _accountingMonthBounds.month,
                              ),
                              onChanged: (month) =>
                                  setState(() => _accountingMonth = month),
                            ),
                            if (!_accountingMonth.isSameMonth(_dateTime)) ...[
                              const SizedBox(height: AppSizes.sm),
                              Container(
                                padding: const EdgeInsets.all(AppSizes.md),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusMd,
                                  ),
                                  border: Border.all(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.warning,
                                      size: AppSizes.iconSm,
                                    ),
                                    const SizedBox(width: AppSizes.sm),
                                    Expanded(
                                      child: Text(
                                        'This was made on ${_dateTime.fullDate}, but won\'t count in ${_dateTime.monthYear}\'s '
                                        'totals — instead it\'ll count in ${_accountingMonth.monthYear}\'s Budget, Cash Flow, '
                                        'Dashboard, and Reports.',
                                        style: context.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _BottomSaveBar(
              label: _isEditing ? 'Save changes' : 'Save Expense',
              isLoading: _isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small required-field label ("Category *") shared by every field in
/// [_DetailsCard] that needs one — a single place for the asterisk style
/// instead of three copy-pasted `Text.rich` blocks.
Widget _requiredLabel(BuildContext context, String text) {
  return Text.rich(
    TextSpan(
      text: text,
      style: _fieldLabelStyle(context),
      children: const [
        TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
      ],
    ),
  );
}

/// The small muted label style every field label in [_DetailsCard] shares
/// (Category/Date/Payment Method's required labels, Person's optional one)
/// — one place for the "quiet caption above a bold value" language every
/// row on this screen uses.
TextStyle? _fieldLabelStyle(BuildContext context) {
  return context.textTheme.labelMedium?.copyWith(
    color: context.colors.onSurface.withValues(alpha: 0.65),
  );
}

/// The accent color for a thin border/small text sitting on a *light,
/// ordinary* surface (as opposed to [_Hero]'s dark card) — mirrors
/// `app_theme.dart`'s own `onSurfaceAccent` formula exactly, because that
/// file documents why: the brand lime is a light, low-saturation-contrast
/// color, so a lime hairline border or lime label text is barely visible on
/// a white/light card in light mode (it only reads clearly as a *fill*,
/// e.g. a button or a tinted wash, or directly on a dark surface). A
/// near-black line/text is used in light mode instead; dark mode uses lime
/// directly, where it has full contrast.
Color _selectionAccent(BuildContext context) {
  return context.isDarkMode ? AppColors.lime : context.colors.onSurface;
}

/// A compact interactive attribute tile — icon badge top-left, chevron
/// top-right, small label + bold value below. Used for Category and Date,
/// side by side, as the app's own lightweight "transaction attribute"
/// control instead of a generic full-width form row: each tile is its own
/// flat bordered surface (matching the app's real `cardTheme` — background +
/// thin outline, no shadow), so no extra divider lines are needed to
/// communicate where one field ends and the next begins.
class _AttributeTile extends StatelessWidget {
  const _AttributeTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.filled,
    required this.onTap,
    this.iconTint,
    this.errorText,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Whether [value] is real selected data (bold, full-strength text) or
  /// still a placeholder prompt like "Select a category" (regular weight,
  /// muted) — the empty state should visibly read as "needs input", the
  /// selected state should read as an actual transaction attribute. Date
  /// always passes `true`: a transaction always has a date, so there is no
  /// genuine empty state for it.
  final bool filled;
  final VoidCallback onTap;

  /// The category's own color, when one is selected — `null` renders a
  /// neutral lime-tinted badge instead (Date always passes `null`, since a
  /// date has no inherent color of its own).
  final Color? iconTint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = errorText != null;
    final badgeColor = iconTint ?? colors.primary;
    final iconColor = iconTint ?? _selectionAccent(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: colors.primary.withValues(alpha: 0.12),
            highlightColor: colors.primary.withValues(alpha: 0.06),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: hasError ? colors.error : colors.outline,
                ),
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusSm,
                          ),
                        ),
                        child: Icon(icon, size: 13, color: iconColor),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 13,
                        color: colors.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xs + 2),
                  Text(label, style: _fieldLabelStyle(context)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: filled ? FontWeight.w800 : FontWeight.w600,
                      color: hasError
                          ? colors.error
                          : filled
                          ? colors.onSurface
                          : colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorText!,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// The hero-surface palette for Type/Amount/Description — the same values
/// `app_theme.dart` feeds into [FlowFiColors] for the dashboard's balance
/// card, referenced directly here rather than via `context.flowfi` so this
/// dark card doesn't depend on the app's [ThemeExtension] being registered
/// (a plain `MaterialApp(theme: ThemeData())`, as several existing widget
/// tests use, has no [FlowFiColors] and would otherwise null-check-crash).
/// Values are identical in light and dark mode by design — this surface is
/// always near-black — so a fixed palette is correct here either way.
abstract class _Hero {
  _Hero._();

  static const surface = AppColors.nearBlack;
  static const surfaceRaised = AppColors.raisedDark;
  static const onSurface = Colors.white;
  static final onSurfaceMuted = Colors.white.withValues(alpha: 0.64);
  static const accent = AppColors.lime;
  static const onAccent = AppColors.onLime;
}

/// The dark "hero surface" wrapper for Type/Amount/Description — the same
/// near-black identity the dashboard's balance card uses, so Add Expense's
/// single most important field gets its own premium, unmistakable focal
/// point (and, since this surface is near-black in *both* themes by design,
/// it looks intentional rather than inverted when the app is in light
/// mode).
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // _Hero constants used directly below.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.md,
        AppSizes.lg,
        AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: _Hero.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: AppShadows.soft(context),
      ),
      child: child,
    );
  }
}

/// Compact animated pill toggle for Expense/Income/Transfer — a sliding
/// accent-filled indicator behind the active segment, themed for the dark
/// [_HeroCard] surface it sits on instead of Material's default
/// [SegmentedButton] look (which reads flat/dated against a dark card).
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});

  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    // _Hero constants used directly below.
    final types = TransactionType.values;
    final index = types.indexOf(value);

    return SizedBox(
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _Hero.surfaceRaised,
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                types.length > 1 ? -1 + 2 * index / (types.length - 1) : 0,
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / types.length,
                heightFactor: 1,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _Hero.accent,
                    borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final type in types)
                  Expanded(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppSizes.radiusPill,
                        ),
                        onTap: () => onChanged(type),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                type.icon,
                                size: 14,
                                color: type == value
                                    ? _Hero.onAccent
                                    : _Hero.onSurfaceMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                type.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: type == value
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: type == value
                                      ? _Hero.onAccent
                                      : _Hero.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The Description field's decoration while it sits inside [_HeroCard] — a
/// raised-on-hero fill (one step lighter than the hero surface itself,
/// matching [FlowFiColors.heroSurfaceRaised]'s existing "nested element on a
/// dark surface" role) instead of [_premiumDecoration]'s light-surface
/// colors, which would have no contrast against the dark card.
InputDecoration _heroFieldDecoration(
  BuildContext context, {
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  // _Hero constants used directly below.
  return InputDecoration(
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: _Hero.surfaceRaised,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: _Hero.accent, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: context.colors.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: context.colors.error, width: 1.6),
    ),
  );
}

/// One bordered, flat surface grouping a handful of related list rows
/// (Category/Date/Payment Method/Share Expense, or Person/owed-toggle) —
/// separation between the rows inside comes from a hairline [_RowDivider],
/// not from each row getting its own filled background, so the screen
/// doesn't read as a stack of near-identical pale boxes. A soft shadow adds
/// restrained depth on top of the border, echoing [_HeroCard] without
/// competing with it (see `AppShadows.soft`'s doc comment on the two-tier
/// shadow system this app uses).
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: context.colors.outline),
        boxShadow: AppShadows.soft(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A faint separator between rows inside [_DetailsCard] — grouping comes
/// mainly from spacing and the card's own boundary, so this stays a low-
/// contrast hairline rather than a strong visible line.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: AppSizes.md,
      thickness: 1,
      color: context.colors.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

/// One tap-to-pick row — a leading icon, an optional small label above a
/// value string, and a trailing chevron. No fill/border of its own — an
/// [InkWell] ripple is the only feedback; the caller supplies any
/// surrounding surface (e.g. Share Expense's own bordered tile).
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    required this.onTap,
    this.leadingIcon,
    this.value,
    this.valueEmphasis = false,
    this.subtitle,
    this.horizontalPadding = 0,
  });

  final Widget? label;
  final VoidCallback onTap;
  final IconData? leadingIcon;
  final String? value;
  final bool valueEmphasis;
  final String? subtitle;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: AppSizes.sm,
          ),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: AppSizes.iconMd,
                  color: colors.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: AppSizes.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?label,
                    if (value != null)
                      Text(
                        value!,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: valueEmphasis
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row that starts collapsed to a single compact line (an icon + label,
/// e.g. "+ Add note" / "Advanced options ›") and expands in place to reveal
/// [child] — the mechanism behind both the Notes field and Advanced Options,
/// so neither secondary section costs any vertical space on the fast path
/// until the user deliberately opens it.
class _CollapsibleRow extends StatelessWidget {
  const _CollapsibleRow({
    required this.expanded,
    required this.collapsedIcon,
    required this.collapsedLabel,
    required this.expandedLabel,
    required this.onToggle,
    required this.child,
  });

  final bool expanded;
  final IconData collapsedIcon;
  final String collapsedLabel;
  final String expandedLabel;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                child: Row(
                  children: [
                    Icon(
                      expanded ? Icons.tune_rounded : collapsedIcon,
                      size: AppSizes.iconSm,
                      color: expanded
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(
                        expanded ? expandedLabel : collapsedLabel,
                        style: context.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      turns: expanded ? 0.5 : 0,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The filled, thin-bordered field decoration this screen's text fields
/// share (Description, Notes) — matches the app's real `inputDecorationTheme`
/// surface + outline language instead of an ad hoc alpha overlay with no
/// border, so text fields and the [_DetailsCard] rows read as one system.
InputDecoration _premiumDecoration(
  BuildContext context, {
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final colors = context.colors;
  return InputDecoration(
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.6),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.6),
    ),
  );
}

/// The persistent bottom action bar — a hairline-topped surface holding the
/// full-width [PrimaryButton], pinned below the scroll instead of living at
/// its end, so the primary action is always reachable without scrolling.
class _BottomSaveBar extends StatelessWidget {
  const _BottomSaveBar({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outline)),
        boxShadow: AppShadows.soft(context),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.sm,
          AppSizes.lg,
          AppSizes.sm,
        ),
        child: PrimaryButton(
          label: label,
          isLoading: isLoading,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Searchable list of categories, opened from the Category row — easier to
/// scan and tap with one hand than the old icon grid, and stays usable as
/// the category count grows since the search box filters by name.
class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedId,
  });

  final List<Category> categories;
  final String? selectedId;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.categories
        : widget.categories
              .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (sheetContext, scrollController) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSizes.sm),
              Text('Select category', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search categories',
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: AppSizes.iconSm,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: AppSizes.iconSm,
                          ),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSizes.xs),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No categories match "$_query"',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colors.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final category = filtered[index];
                          final color = Color(category.colorValue);
                          final selected = category.id == widget.selectedId;
                          return ListTile(
                            onTap: () => Navigator.of(context).pop(category.id),
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Icon(
                                category.icon,
                                color: color,
                                size: AppSizes.iconSm,
                              ),
                            ),
                            title: Text(category.name),
                            trailing: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: context.colors.primary,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Optional "associate this expense with a person" row — sets
/// [Transaction.linkedPersonId] as a plain reference by default (no
/// [Expense], ledger entry, loan, or EMI). The sibling "This person owes me
/// this expense" switch shown just below (only once a person is picked) is
/// the only thing that routes this expense through
/// [ExpenseRepository.assignToPerson]/`convertToAssigned` for a real ledger
/// effect — this field itself never does.
class _PersonField extends ConsumerWidget {
  const _PersonField({
    required this.personId,
    required this.onTap,
    required this.onClear,
  });

  final String? personId;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final person = personId == null
        ? null
        : people.where((p) => p.id == personId).firstOrNull;

    // Plain list row — no fill/border of its own, matching [_TapRow]'s
    // language, since this lives inside a [_DetailsCard] that already
    // provides the surface + border grouping.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
          child: Row(
            children: [
              if (person != null) ...[
                PersonAvatar(
                  name: person.name,
                  colorValue: person.avatarColorValue,
                  radius: 13,
                ),
                const SizedBox(width: AppSizes.sm),
              ] else ...[
                Icon(
                  Icons.person_add_alt_1_rounded,
                  size: AppSizes.iconMd,
                  color: context.colors.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: AppSizes.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Person (optional)', style: _fieldLabelStyle(context)),
                    Text(
                      person?.name ?? 'Add a person (optional)',
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (person != null)
                IconButton(
                  icon: const Icon(Icons.cancel, size: AppSizes.iconSm),
                  onPressed: onClear,
                  tooltip: 'Remove person',
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.onSurface.withValues(alpha: 0.35),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Splits an [accountPickerLabel] string into a primary name and, when the
/// label ends in a masked-digits suffix (`• ****4201` or `**5678`), a
/// secondary line — so a payment option can show "HDFC" / "•••• 4201" as
/// two visually distinct lines instead of one run-on string. Purely a
/// display split; the underlying label/account data is unchanged.
({String primary, String? secondary}) _splitAccountLabel(String label) {
  final match = RegExp(r'[•]?\s*(\*{2,}\s*\d+)\s*$').firstMatch(label);
  if (match == null) return (primary: label, secondary: null);
  final secondary = '•••• ${match.group(1)!.replaceAll(RegExp(r'[^\d]'), '')}';
  final primary = label.substring(0, match.start).trim();
  return (primary: primary.isEmpty ? label : primary, secondary: secondary);
}

class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({
    required this.account,
    required this.creditCards,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final List<CreditCardProfile> creditCards;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = _splitAccountLabel(accountPickerLabel(account, creditCards));
    final isLogo =
        account.type == AccountType.bank || account.type == AccountType.card;
    final accent = _selectionAccent(context);
    // Selected state stacks several cues — a visibly thicker accent border,
    // a lime-tinted fill/icon backdrop, bolder text, and a checkmark — so it
    // reads as obviously selected next to several similar-shaped chips. The
    // border/text use [_selectionAccent] rather than raw `colors.primary`:
    // lime is a fill/dark-surface color, not a light-surface line/text
    // color (see that helper's doc comment) — the *fill* wash and checkmark
    // still use lime directly, which is the one place it's meant to be used
    // this way.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.xs + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.16)
                : colors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: selected ? accent : colors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.all(isLogo && selected ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? colors.primary.withValues(alpha: 0.18)
                      : Colors.transparent,
                ),
                child: isLogo
                    ? BankLogo(
                        bankId: account.bankId,
                        fallbackName: account.name,
                        size: AppSizes.iconMd,
                      )
                    : Icon(
                        account.type.icon,
                        size: AppSizes.iconMd,
                        color: selected
                            ? accent
                            : colors.onSurface.withValues(alpha: 0.6),
                      ),
              ),
              const SizedBox(width: AppSizes.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    parts.primary,
                    style: context.textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  if (parts.secondary != null)
                    Text(
                      parts.secondary!,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.onSurface.withValues(
                          alpha: selected ? 0.7 : 0.55,
                        ),
                        letterSpacing: 0.3,
                      ),
                    ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: AppSizes.sm),
                Icon(
                  Icons.check_circle_rounded,
                  size: AppSizes.iconSm,
                  color: colors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
