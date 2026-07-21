import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/bill.dart';
import '../../domain/bill_recurrence.dart';
import '../providers/bill_providers.dart';

/// Every offset selectable in the reminder multi-select, per the brief's
/// fixed set (Today/Tomorrow/3 Days/7 Days) — "Custom Reminder" is covered
/// by editing [Bill.reminderOffsets] to include any additional value, but
/// this sheet only exposes the four standard toggles for simplicity.
const _reminderOffsetChoices = [0, 1, 3, 7];

/// Bottom sheet for creating or editing a bill.
class BillFormSheet extends ConsumerStatefulWidget {
  const BillFormSheet({super.key, this.bill});

  final Bill? bill;

  static Future<void> show(BuildContext context, {Bill? bill}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => BillFormSheet(bill: bill),
    );
  }

  @override
  ConsumerState<BillFormSheet> createState() => _BillFormSheetState();
}

class _BillFormSheetState extends ConsumerState<BillFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.bill?.name);
  late final _amountController = TextEditingController(
    text: widget.bill == null ? '' : widget.bill!.amount.toStringAsFixed(2),
  );
  late final _customDaysController = TextEditingController(
    text: widget.bill?.customIntervalDays?.toString() ?? '',
  );
  late final _notesController = TextEditingController(text: widget.bill?.notes ?? '');
  late DateTime _dueDate = widget.bill?.dueDate ?? DateTime.now();
  late BillRecurrence _recurrence = widget.bill?.recurrence ?? BillRecurrence.monthly;
  late String? _accountId = widget.bill?.accountId;
  late String? _categoryId = widget.bill?.categoryId;
  final Set<int> _reminderOffsets = {};
  final _amountFocusNode = FocusNode();
  bool _isSaving = false;

  bool get _isEditing => widget.bill != null;

  @override
  void initState() {
    super.initState();
    _reminderOffsets.addAll(widget.bill?.reminderOffsets ?? const [1, 3]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _customDaysController.dispose();
    _notesController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(billRepositoryProvider);
      final customDays = _recurrence == BillRecurrence.custom
          ? int.tryParse(_customDaysController.text.trim())
          : null;
      final sortedOffsets = _reminderOffsets.toList()..sort();

      if (_isEditing) {
        await repository.editBill(
          widget.bill!,
          name: _nameController.text.trim(),
          amount: double.parse(_amountController.text.trim()),
          dueDate: _dueDate,
          recurrence: _recurrence,
          accountId: _accountId,
          categoryId: _categoryId,
          customIntervalDays: customDays,
          reminderOffsets: sortedOffsets,
          notes: _notesController.text.trim(),
        );
      } else {
        await repository.createBill(
          name: _nameController.text.trim(),
          amount: double.parse(_amountController.text.trim()),
          dueDate: _dueDate,
          recurrence: _recurrence,
          accountId: _accountId,
          categoryId: _categoryId,
          customIntervalDays: customDays,
          reminderOffsets: sortedOffsets,
          notes: _notesController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save bill: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.expense));

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
                _isEditing ? 'Edit bill' : 'Add bill',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Bill name'),
                validator: Validators.required,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _amountFocusNode.requestFocus(),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _amountController,
                focusNode: _amountFocusNode,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.md),
              OutlinedButton.icon(
                onPressed: _pickDueDate,
                icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                label: Text('Due ${_dueDate.fullDate}'),
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<BillRecurrence>(
                initialValue: _recurrence,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: [
                  for (final recurrence in BillRecurrence.values)
                    DropdownMenuItem(value: recurrence, child: Text(recurrence.label)),
                ],
                onChanged: (value) => setState(() => _recurrence = value ?? _recurrence),
              ),
              if (_recurrence == BillRecurrence.custom) ...[
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: _customDaysController,
                  decoration: const InputDecoration(labelText: 'Repeat every N days'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) return 'Enter a whole number of days';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: AppSizes.md),
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load accounts: $error'),
                data: (accounts) {
                  final validId = accounts.any((a) => a.id == _accountId) ? _accountId : null;
                  return DropdownButtonFormField<String>(
                    initialValue: validId,
                    decoration: const InputDecoration(labelText: 'Account (optional)'),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(value: account.id, child: Text(account.name)),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  );
                },
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String>(
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: const InputDecoration(labelText: 'Category (optional)'),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: AppSizes.md),
              Text('Remind me', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSizes.xs),
              Wrap(
                spacing: AppSizes.sm,
                children: [
                  for (final offset in _reminderOffsetChoices)
                    FilterChip(
                      label: Text(offset == 0 ? 'Today' : offset == 1 ? 'Tomorrow' : '$offset days before'),
                      selected: _reminderOffsets.contains(offset),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _reminderOffsets.add(offset);
                        } else {
                          _reminderOffsets.remove(offset);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add bill',
                isLoading: _isSaving,
                onPressed: _save,
              ),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
