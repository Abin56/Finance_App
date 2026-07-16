import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/month_year_stepper.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../expense/presentation/widgets/split_expense_form_sheet.dart';
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
  late TransactionType _type = widget.transaction?.type ?? widget.initialType ?? TransactionType.expense;
  late DateTime _dateTime = widget.transaction?.dateTime ?? widget.smsPrefill?.dateTime ?? DateTime.now();
  late String? _accountId = widget.transaction?.accountId ?? widget.smsPrefill?.suggestedAccountId;
  late String? _categoryId = widget.transaction?.categoryId ?? widget.smsPrefill?.suggestedCategoryId;
  late bool _excludeFromCalculations = widget.transaction?.excludeFromCalculations ?? false;

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

  /// Closes this screen and opens [SplitExpenseFormSheet] in its place —
  /// same "Add Expense" entry point, just routed to the existing split
  /// engine instead of a plain transaction, with no logic duplicated here.
  Future<void> _switchToSplitExpense(BuildContext context) async {
    Navigator.of(context).pop();
    await SplitExpenseFormSheet.show(context);
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

      if (_isEditing) {
        await repository.editTransaction(
          widget.transaction!,
          type: _type,
          amount: amount,
          dateTime: _dateTime,
          accountId: _accountId,
          categoryId: _categoryId,
          description: description,
          notes: widget.transaction!.notes,
          excludeFromCalculations: _excludeFromCalculations,
          accountingMonth: accountingMonth,
          clearAccountingMonth: accountingMonth == null,
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
                title: const Text('Exclude from Financial Calculations'),
                subtitle: const Text(
                  "This transaction will be saved in your history but won't affect balances, reports, budgets, or analytics.",
                ),
                value: _excludeFromCalculations,
                onChanged: (value) => setState(() => _excludeFromCalculations = value),
              ),
              const SizedBox(height: AppSizes.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accounting Month'),
                subtitle: Text(
                  _customAccountingMonth
                      ? 'Move to another month'
                      : 'Same as Transaction Date (${_dateTime.monthYear})',
                ),
                value: _customAccountingMonth,
                onChanged: (value) => setState(() {
                  _customAccountingMonth = value;
                  if (!value) _accountingMonth = DateTime(_dateTime.year, _dateTime.month);
                }),
              ),
              if (_customAccountingMonth) ...[
                const SizedBox(height: AppSizes.sm),
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
                            'This transaction was made on ${_dateTime.fullDate}.\n'
                            'It will NOT be included in ${_dateTime.monthYear} calculations.\n'
                            'It will appear in ${_accountingMonth.monthYear} Budget, Cash Flow, Dashboard, and Reports.',
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
