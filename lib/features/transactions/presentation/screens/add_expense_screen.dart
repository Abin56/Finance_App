import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/month_year_stepper.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
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
  const AddExpenseScreen({super.key, this.transaction, this.smsPrefill, this.initialType});

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
        builder: (_) => AddExpenseScreen(transaction: transaction, smsPrefill: smsPrefill, initialType: initialType),
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
        : (widget.smsPrefill == null ? '' : widget.smsPrefill!.amount.toStringAsFixed(2)),
  );
  late final _descriptionController = TextEditingController(
    text: widget.transaction?.description ?? widget.smsPrefill?.merchantOrSender ?? '',
  );
  final _descriptionFocusNode = FocusNode();
  late TransactionType _type = widget.transaction?.type ?? widget.initialType ?? TransactionType.expense;
  late DateTime _dateTime = widget.transaction?.dateTime ?? widget.smsPrefill?.dateTime ?? DateTime.now();
  late String? _accountId = widget.transaction?.accountId ?? widget.smsPrefill?.suggestedAccountId;
  late String? _categoryId = widget.transaction?.categoryId ?? widget.smsPrefill?.suggestedCategoryId;
  late bool _excludeFromCalculations = widget.transaction?.excludeFromCalculations ?? false;
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
  late bool _customAccountingMonth = widget.transaction?.accountingMonth != null;
  late DateTime _accountingMonth = widget.transaction?.accountingMonth ?? DateTime(_dateTime.year, _dateTime.month);
  bool _isSaving = false;
  String? _accountError;
  String? _categoryError;

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

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
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
      _dateTime = DateTime(picked.year, picked.month, picked.day, _dateTime.hour, _dateTime.minute);
      // Keep the default ("Same as Transaction Date") in sync with the new
      // date — only meaningful while the user hasn't opted into a custom
      // Accounting Month.
      if (!_customAccountingMonth) _accountingMonth = DateTime(_dateTime.year, _dateTime.month);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(_dateTime.year, _dateTime.month, _dateTime.day, picked.hour, picked.minute);
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
      builder: (sheetContext) => _CategoryPickerSheet(categories: categories, selectedId: _categoryId),
    );
    if (picked == null) return;
    setState(() {
      _categoryId = picked;
      _categoryError = null;
    });
  }

  /// Opens [AddExpenseChooser] on top of this still-live screen, carrying
  /// over everything already typed here — same "Add Expense" entry point,
  /// just routed to the existing split/assign engine instead of a plain
  /// transaction, with no logic duplicated here. Deliberately does NOT pop
  /// this screen first: if the user backs out of the chooser/sheet without
  /// saving, they land right back on this form with every field intact. Only
  /// a genuine save closes this screen too, so they don't end up stuck on a
  /// stale empty form after the shared expense already went through.
  Future<void> _switchToSplitExpense(BuildContext context) async {
    final draft = AddExpenseDraftPrefill(
      amount: double.tryParse(_amountController.text.trim()),
      description: _descriptionController.text.trim(),
      categoryId: _categoryId,
      accountId: _accountId,
      date: _dateTime,
      excludeFromCalculations: _excludeFromCalculations,
      accountingMonth: _customAccountingMonth ? _accountingMonth : null,
    );
    final saved = await AddExpenseChooser.show(context, draft: draft);
    if (saved == true && context.mounted) Navigator.of(context).pop();
  }

  /// Whether this save should end up "owed" — the toggle only ever applies
  /// to an expense with a linked person; switching type away from Expense or
  /// clearing the person always forces it back off, so an edit can never
  /// leave a stray owed [Expense] behind a non-expense/unlinked transaction.
  bool get _effectiveOwesToggle => _owesPersonToggle && _linkedPersonId != null && _type == TransactionType.expense;

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
  Future<void> _convertExistingToOwed(Transaction transaction, String description) async {
    final people = ref.read(peopleStreamProvider).value ?? const [];
    final person = people.where((p) => p.id == _linkedPersonId).firstOrNull;
    final existingExpense = ref.read(expenseForTransactionProvider(transaction.id));
    final expenseRepository = ref.read(expenseRepositoryProvider);
    await expenseRepository.convertToAssigned(
      existingExpense: existingExpense,
      transactionId: transaction.id,
      description: description.isNotEmpty ? description : 'Expense',
      totalAmount: double.parse(_amountController.text.trim()),
      date: _dateTime,
      categoryId: _categoryId!,
      accountId: _accountId!,
      notes: transaction.notes,
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
  Future<void> _editExistingOwed(Transaction transaction, String description) async {
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
        : ref.read(installmentsStreamProvider(expense.scheduleId!)).value ?? const <Installment>[];
    await ref.read(expenseRepositoryProvider).editExpense(
          expense: expense,
          currentInstallments: currentInstallments,
          description: description.isNotEmpty ? description : 'Expense',
          totalAmount: totalAmount,
          date: _dateTime,
          categoryId: _categoryId,
          accountId: _accountId,
          notes: transaction.notes,
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
      final description = _descriptionController.text.trim();

      final accountingMonth = _customAccountingMonth ? _accountingMonth : null;
      final wasOwed = _initialOwesPersonToggle && _initialLinkedPersonId != null;
      final nowOwed = _effectiveOwesToggle;

      if (_isEditing) {
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
            notes: transaction.notes,
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
            notes: transaction.notes,
            excludeFromCalculations: _excludeFromCalculations,
            accountingMonth: accountingMonth,
            clearAccountingMonth: accountingMonth == null,
            linkedPersonId: _linkedPersonId,
            clearLinkedPersonId: _linkedPersonId == null,
            owesPersonToggle: false,
          );
        }
      } else if (nowOwed) {
        final people = ref.read(peopleStreamProvider).value ?? const [];
        final person = people.where((p) => p.id == _linkedPersonId).firstOrNull;
        final expenseRepository = ref.read(expenseRepositoryProvider);
        final expense = await expenseRepository.assignToPerson(
          description: description,
          totalAmount: amount,
          date: _dateTime,
          categoryId: _categoryId!,
          accountId: _accountId!,
          personId: _linkedPersonId!,
          personName: person?.name ?? '',
          notes: widget.smsPrefill?.note ?? '',
          excludeFromCalculations: _excludeFromCalculations,
          accountingMonth: accountingMonth,
        );
        final createdTransaction = await repository.getByKey(expense.transactionId);
        if (createdTransaction != null) {
          await repository.editTransaction(
            createdTransaction,
            linkedPersonId: _linkedPersonId,
            owesPersonToggle: true,
          );
        }

        await completeSmsImport(
          ref,
          smsPrefill: widget.smsPrefill,
          linkedEntityId: expense.transactionId,
          learnCategoryType: _type,
          learnCategoryId: _categoryId,
        );
      } else {
        final created = await repository.createTransaction(
          type: _type,
          amount: amount,
          dateTime: _dateTime,
          accountId: _accountId!,
          categoryId: _categoryId!,
          description: description,
          notes: widget.smsPrefill?.note ?? '',
          excludeFromCalculations: _excludeFromCalculations,
          accountingMonth: accountingMonth,
          linkedPersonId: _linkedPersonId,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save expense: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesForTypeProvider(_type));
    final selectedCategory = categories.where((c) => c.id == _categoryId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Expense' : 'Add Expense'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text('Save', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: AppSizes.lg,
            right: AppSizes.lg,
            top: AppSizes.md,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TransactionType>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final type in TransactionType.values)
                    ButtonSegment(value: type, label: Text(type.label), icon: Icon(type.icon)),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() {
                    _type = selection.first;
                    if (_categoryId != null &&
                        !categories.any((c) => c.id == _categoryId)) {
                      _categoryId = null;
                    }
                  });
                },
              ),
              const SizedBox(height: AppSizes.md),
              Text('Amount', style: context.textTheme.titleSmall),
              const SizedBox(height: AppSizes.xs),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                  isDense: true,
                ),
                style: context.textTheme.titleLarge,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _descriptionFocusNode.requestFocus(),
              ),
              const SizedBox(height: AppSizes.md),
              Text.rich(
                TextSpan(
                  text: 'Description',
                  style: context.textTheme.titleSmall,
                  children: const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))],
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              TextFormField(
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                decoration: InputDecoration(
                  prefixIcon: selectedCategory == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.all(AppSizes.sm),
                          child: CircleAvatar(
                            backgroundColor: Color(selectedCategory.colorValue).withValues(alpha: 0.15),
                            child: Icon(selectedCategory.icon, color: Color(selectedCategory.colorValue), size: AppSizes.iconSm),
                          ),
                        ),
                  suffixIcon: _descriptionController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.cancel, size: AppSizes.iconSm),
                          onPressed: () => setState(_descriptionController.clear),
                        ),
                ),
                maxLength: 100,
                validator: Validators.required,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              if (_type == TransactionType.expense) ...[
                const SizedBox(height: AppSizes.sm),
                Text('Person (optional)', style: context.textTheme.titleSmall),
                const SizedBox(height: AppSizes.xs),
                _PersonField(
                  personId: _linkedPersonId,
                  onTap: _pickPerson,
                  onClear: _clearPerson,
                ),
                if (_linkedPersonId != null) ...[
                  const SizedBox(height: AppSizes.xs),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This person owes me this expense'),
                    subtitle: const Text(
                      "Adds this amount to what they owe you, so it shows up when you check their balance later.",
                    ),
                    value: _owesPersonToggle,
                    onChanged: (value) => setState(() => _owesPersonToggle = value),
                  ),
                ],
              ],
              const SizedBox(height: AppSizes.sm),
              Text.rich(
                TextSpan(
                  text: 'Category',
                  style: context.textTheme.titleSmall,
                  children: const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))],
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              InkWell(
                onTap: () => _pickCategory(categories),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                child: InputDecorator(
                  decoration: InputDecoration(errorText: _categoryError, isDense: true),
                  child: Row(
                    children: [
                      if (selectedCategory != null) ...[
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: Color(selectedCategory.colorValue).withValues(alpha: 0.15),
                          child: Icon(selectedCategory.icon, color: Color(selectedCategory.colorValue), size: AppSizes.iconSm),
                        ),
                        const SizedBox(width: AppSizes.sm),
                      ],
                      Expanded(
                        child: Text(
                          selectedCategory?.name ?? 'Select a category',
                          style: context.textTheme.bodyMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: AppSizes.iconMd),
                    ],
                  ),
                ),
              ),
              if (_activeCategorySuggestion case final source?)
                SmsSuggestionHint(source: source, merchant: widget.smsPrefill?.merchantOrSender),
              const SizedBox(height: AppSizes.sm),
              Text.rich(
                TextSpan(
                  text: 'Date & Time',
                  style: context.textTheme.titleSmall,
                  children: const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))],
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                      label: Text(_dateTime.fullDate),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time_outlined, size: AppSizes.iconSm),
                      label: Text(TimeOfDay.fromDateTime(_dateTime).format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Text.rich(
                TextSpan(
                  text: 'Payment Method',
                  style: context.textTheme.titleSmall,
                  children: const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))],
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load payment methods: $error'),
                data: (accounts) {
                  return Wrap(
                    spacing: AppSizes.sm,
                    runSpacing: AppSizes.sm,
                    children: [
                      for (final account in accounts)
                        _PaymentMethodChip(
                          account: account,
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
                Text(_accountError!, style: TextStyle(color: context.colors.error, fontSize: 12)),
              ],
              if (!_isEditing && _type == TransactionType.expense) ...[
                const SizedBox(height: AppSizes.md),
                InkWell(
                  onTap: () => _switchToSplitExpense(context),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  child: InputDecorator(
                    decoration: const InputDecoration(isDense: true),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline_rounded, color: context.colors.primary),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Share Expense'),
                              Text(
                                'Share this with others',
                                style: context.textTheme.bodySmall
                                    ?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Don't count this in my totals"),
                subtitle: const Text(
                  "Still shows in your history — just won't affect your balance, budgets, or reports.",
                ),
                value: _excludeFromCalculations,
                onChanged: (value) => setState(() => _excludeFromCalculations = value),
              ),
              const SizedBox(height: AppSizes.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Count this in a different month?'),
                subtitle: Text(
                  _customAccountingMonth
                      ? 'Choose which month it should count toward below.'
                      : 'Right now: counted in ${_dateTime.monthYear} (same as the date above)',
                ),
                value: _customAccountingMonth,
                onChanged: (value) => setState(() {
                  _customAccountingMonth = value;
                  if (!value) _accountingMonth = DateTime(_dateTime.year, _dateTime.month);
                }),
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
                  min: DateTime(_accountingMonthBounds.year - 5, _accountingMonthBounds.month),
                  max: DateTime(_accountingMonthBounds.year + 2, _accountingMonthBounds.month),
                  onChanged: (month) => setState(() => _accountingMonth = month),
                ),
                if (!_accountingMonth.isSameMonth(_dateTime)) ...[
                  const SizedBox(height: AppSizes.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: AppSizes.iconSm),
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
              const SizedBox(height: AppSizes.lg),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Save Expense',
                isLoading: _isSaving,
                onPressed: _save,
              ),
              const SizedBox(height: AppSizes.xs),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable list of categories, opened from the Category row — easier to
/// scan and tap with one hand than the old icon grid, and stays usable as
/// the category count grows since the search box filters by name.
class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.categories, required this.selectedId});

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
        : widget.categories.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();

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
                  prefixIcon: const Icon(Icons.search_rounded, size: AppSizes.iconSm),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: AppSizes.iconSm),
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
                          style: context.textTheme.bodyMedium
                              ?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
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
                              child: Icon(category.icon, color: color, size: AppSizes.iconSm),
                            ),
                            title: Text(category.name),
                            trailing: selected ? Icon(Icons.check_rounded, color: context.colors.primary) : null,
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
  const _PersonField({required this.personId, required this.onTap, required this.onClear});

  final String? personId;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final person = personId == null ? null : people.where((p) => p.id == personId).firstOrNull;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InputDecorator(
        decoration: const InputDecoration(isDense: true),
        child: Row(
          children: [
            if (person != null) ...[
              PersonAvatar(name: person.name, colorValue: person.avatarColorValue, radius: 13),
              const SizedBox(width: AppSizes.sm),
            ],
            Expanded(
              child: Text(
                person?.name ?? 'Add a person (optional)',
                style: context.textTheme.bodyMedium,
              ),
            ),
            if (person != null)
              IconButton(
                icon: const Icon(Icons.cancel, size: AppSizes.iconSm),
                onPressed: onClear,
                tooltip: 'Remove person',
              )
            else
              const Icon(Icons.chevron_right_rounded, size: AppSizes.iconMd),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({required this.account, required this.selected, required this.onTap});

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(account.name),
      avatar: account.type == AccountType.bank || account.type == AccountType.card
          ? BankAvatar(bankId: account.bankId, fallbackName: account.name, size: AppSizes.iconSm + 2)
          : Icon(account.type.icon, size: AppSizes.iconSm),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: context.colors.primary.withValues(alpha: 0.15),
      side: BorderSide(color: selected ? context.colors.primary : context.colors.outline),
    );
  }
}
