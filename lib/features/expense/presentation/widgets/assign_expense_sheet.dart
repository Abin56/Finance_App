import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/month_year_stepper.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../providers/expense_providers.dart';
import 'split_expense_form_sheet.dart' show AddExpenseDraftPrefill;

/// Simpler bottom sheet (Task 2) for assigning an entire expense to a
/// single existing person — the degenerate single-participant case of
/// [SplitExpenseFormSheet], so this just collects the plain expense
/// fields plus one required person picker and calls
/// `ExpenseRepository.assignToPerson`.
class AssignExpenseSheet extends ConsumerStatefulWidget {
  const AssignExpenseSheet({super.key, this.smsPrefill, this.initialPerson, this.draft});

  /// Set when opened from the SMS Inbox's "Paid for Someone Else" option —
  /// seeds description/amount/date/account/category as normal editable
  /// initial values. The person must still be picked manually.
  final SmsPrefill? smsPrefill;

  /// Set when opened from that person's own Contact Ledger screen — the
  /// person is already known from context, so the picker below is skipped
  /// entirely instead of asking the user to pick who they already picked
  /// by navigating there.
  final Person? initialPerson;

  /// Set when opened from [AddExpenseScreen]'s "Share Expense" row — carries
  /// over everything the user already typed there so switching to "this
  /// person will pay" never re-asks for the same information.
  final AddExpenseDraftPrefill? draft;

  static Future<bool?> show(
    BuildContext context, {
    SmsPrefill? smsPrefill,
    Person? initialPerson,
    AddExpenseDraftPrefill? draft,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AssignExpenseSheet(smsPrefill: smsPrefill, initialPerson: initialPerson, draft: draft),
    );
  }

  @override
  ConsumerState<AssignExpenseSheet> createState() => _AssignExpenseSheetState();
}

class _AssignExpenseSheetState extends ConsumerState<AssignExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _descriptionController = TextEditingController(
    text: widget.smsPrefill?.merchantOrSender ?? widget.draft?.description ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.smsPrefill != null
        ? widget.smsPrefill!.amount.toStringAsFixed(2)
        : (widget.draft?.amount == null ? '' : widget.draft!.amount!.toStringAsFixed(2)),
  );
  late final _notesController = TextEditingController(text: widget.smsPrefill?.note ?? widget.draft?.notes ?? '');
  final _amountFocusNode = FocusNode();
  late DateTime _date = widget.smsPrefill?.dateTime ?? widget.draft?.date ?? DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  late String? _accountId = widget.smsPrefill?.suggestedAccountId ?? widget.draft?.accountId;
  late String? _categoryId = widget.smsPrefill?.suggestedCategoryId ?? widget.draft?.categoryId;
  late String? _personId = widget.initialPerson?.id;
  String? _accountError;
  String? _categoryError;
  String? _personError;
  bool _isSaving = false;
  late bool _excludeFromCalculations = widget.draft?.excludeFromCalculations ?? false;
  late bool _customAccountingMonth = widget.draft?.accountingMonth != null;
  late DateTime _accountingMonth = widget.draft?.accountingMonth ?? DateTime(_date.year, _date.month);

  bool get _personLocked => widget.initialPerson != null;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  Future<void> _save(List<Person> people) async {
    final formValid = _formKey.currentState!.validate();
    setState(() {
      _accountError = _accountId == null ? 'Select an account' : null;
      _categoryError = _categoryId == null ? 'Select a category' : null;
      _personError = _personId == null ? 'Select a person' : null;
    });
    if (!formValid || _accountId == null || _categoryId == null || _personId == null) return;

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(expenseRepositoryProvider);
      final person = people.firstWhere((p) => p.id == _personId);
      final expense = await repository.assignToPerson(
        description: _descriptionController.text.trim(),
        totalAmount: double.parse(_amountController.text.trim()),
        date: _date,
        categoryId: _categoryId!,
        accountId: _accountId!,
        personId: person.id,
        personName: person.name,
        notes: _notesController.text.trim(),
        dueDate: _dueDate,
        excludeFromCalculations: _excludeFromCalculations,
        accountingMonth: _customAccountingMonth ? _accountingMonth : null,
      );

      await completeSmsImport(ref, smsPrefill: widget.smsPrefill, linkedEntityId: expense.transactionId);
      if (mounted) Navigator.of(context).pop(true);
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
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.expense));
    final peopleAsync = ref.watch(peopleStreamProvider);
    final people = peopleAsync.value ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _personLocked ? 'Add expense for ${widget.initialPerson!.name}' : 'Say who will pay this expense',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: Validators.required,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _amountFocusNode.requestFocus(),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _amountController,
                focusNode: _amountFocusNode,
                decoration: const InputDecoration(labelText: 'Total amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.md),
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load accounts: $error'),
                data: (accounts) {
                  final validId = accounts.any((a) => a.id == _accountId) ? _accountId : null;
                  return DropdownButtonFormField<String>(
                    initialValue: validId,
                    decoration: InputDecoration(labelText: 'Account', errorText: _accountError),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(value: account.id, child: Text(account.name)),
                    ],
                    onChanged: (value) => setState(() {
                      _accountId = value;
                      _accountError = null;
                    }),
                  );
                },
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String>(
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: InputDecoration(labelText: 'Category', errorText: _categoryError),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() {
                  _categoryId = value;
                  _categoryError = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),
              if (_personLocked)
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Person'),
                  child: Text(widget.initialPerson!.name),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: people.any((p) => p.id == _personId) ? _personId : null,
                  decoration: InputDecoration(labelText: 'Person', errorText: _personError),
                  items: [
                    for (final person in people)
                      DropdownMenuItem(value: person.id, child: Text(person.name)),
                  ],
                  onChanged: (value) => setState(() {
                    _personId = value;
                    _personError = null;
                  }),
                ),
              const SizedBox(height: AppSizes.md),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                label: Text(_date.fullDate),
              ),
              const SizedBox(height: AppSizes.md),
              Text('Due date', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSizes.xs),
              OutlinedButton.icon(
                onPressed: _pickDueDate,
                icon: const Icon(Icons.event_outlined, size: AppSizes.iconSm),
                label: Text(_dueDate.fullDate),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
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
                      : 'Right now: counted in ${_date.monthYear} (same as the date above)',
                ),
                value: _customAccountingMonth,
                onChanged: (value) => setState(() {
                  _customAccountingMonth = value;
                  if (!value) _accountingMonth = DateTime(_date.year, _date.month);
                }),
              ),
              if (_customAccountingMonth) ...[
                const SizedBox(height: AppSizes.sm),
                MonthYearStepper(
                  value: _accountingMonth,
                  min: DateTime(DateTime.now().year - 5, DateTime.now().month),
                  max: DateTime(DateTime.now().year + 2, DateTime.now().month),
                  onChanged: (month) => setState(() => _accountingMonth = month),
                ),
              ],
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: 'Save',
                isLoading: _isSaving,
                onPressed: () => _save(people),
              ),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
