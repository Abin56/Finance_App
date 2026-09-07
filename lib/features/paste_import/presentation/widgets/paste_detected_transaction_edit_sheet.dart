import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../smart_import/domain/detected_transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../providers/paste_import_providers.dart';

/// Lets the user correct any field a pasted-text row got wrong before it's
/// imported — a copy of Smart Import's `DetectedTransactionEditSheet` wired
/// to [pasteImportControllerProvider] instead, since the original reaches
/// into `smartImportControllerProvider` directly and can't be shared as-is.
class PasteDetectedTransactionEditSheet extends ConsumerStatefulWidget {
  const PasteDetectedTransactionEditSheet._({required this.transaction});

  final DetectedTransaction transaction;

  static Future<void> show(BuildContext context, DetectedTransaction transaction) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PasteDetectedTransactionEditSheet._(transaction: transaction),
    );
  }

  @override
  ConsumerState<PasteDetectedTransactionEditSheet> createState() =>
      _PasteDetectedTransactionEditSheetState();
}

class _PasteDetectedTransactionEditSheetState
    extends ConsumerState<PasteDetectedTransactionEditSheet> {
  late DateTime _date = widget.transaction.date ?? DateTime.now();
  late TransactionType _type = widget.transaction.type ?? TransactionType.expense;
  late final _descriptionController = TextEditingController(
    text: widget.transaction.rawDescription ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.transaction.amount?.toStringAsFixed(2) ?? '',
  );
  late String? _categoryId = widget.transaction.categoryId;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  void _save() {
    final amount = double.tryParse(_amountController.text.trim());
    ref.read(pasteImportControllerProvider.notifier).updateTransaction(
          widget.transaction.id,
          date: _date,
          description: _descriptionController.text.trim(),
          amount: amount,
          type: _type,
          categoryId: _categoryId,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesForTypeProvider(_type));
    if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSizes.lg,
          right: AppSizes.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit transaction', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.md),

              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => setState(() {
                  _type = selection.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),

              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date.fullDate),
              ),
              const SizedBox(height: AppSizes.md),

              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description', isDense: true),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSizes.md),

              TextField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹', isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSizes.md),

              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category', isDense: true),
                hint: const Text('Select a category'),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: AppSizes.lg),

              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
