import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../smart_import/domain/detected_transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../providers/pdf_import_providers.dart';

/// The PDF import "Transaction Details" sheet — a header summarizing the
/// row (icon, description, amount, category · date) followed by editable
/// detail rows (Description, Category, Amount, Type, Date), each opening
/// the same input it always has (a text field, a date picker, a
/// segmented/dropdown chooser) when tapped, plus Delete and Save actions.
/// Redesigned to this row-based "detail sheet" layout per an approved
/// mockup; the underlying edit mechanics are unchanged from the previous
/// all-fields-at-once layout — only how each field is presented/reached.
class PdfDetectedTransactionEditSheet extends ConsumerStatefulWidget {
  const PdfDetectedTransactionEditSheet._({required this.transaction});

  final DetectedTransaction transaction;

  static Future<void> show(
    BuildContext context,
    DetectedTransaction transaction,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          PdfDetectedTransactionEditSheet._(transaction: transaction),
    );
  }

  @override
  ConsumerState<PdfDetectedTransactionEditSheet> createState() =>
      _PdfDetectedTransactionEditSheetState();
}

class _PdfDetectedTransactionEditSheetState
    extends ConsumerState<PdfDetectedTransactionEditSheet> {
  late DateTime _date = widget.transaction.date ?? DateTime.now();
  late TransactionType _type =
      widget.transaction.type ?? TransactionType.expense;
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

  Future<void> _editDescription() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Description',
        initialValue: _descriptionController.text,
        keyboardType: TextInputType.text,
        capitalization: TextCapitalization.words,
      ),
    );
    if (result != null) {
      setState(() => _descriptionController.text = result);
    }
  }

  Future<void> _editAmount() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Amount',
        initialValue: _amountController.text,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        prefixText: '₹',
      ),
    );
    if (result != null) {
      setState(() => _amountController.text = result);
    }
  }

  Future<void> _pickType() async {
    final result = await showModalBottomSheet<TransactionType>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TypePickerSheet(selected: _type),
    );
    if (result != null) {
      setState(() {
        _type = result;
        _categoryId = null;
      });
    }
  }

  Future<void> _pickCategory() async {
    final categories = ref.read(categoriesForTypeProvider(_type));
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CategoryPickerSheet(
        categories: categories,
        selectedId: _categoryId,
      ),
    );
    if (result != null) {
      setState(() => _categoryId = result);
    }
  }

  void _delete() {
    ref
        .read(pdfImportControllerProvider.notifier)
        .removeTransaction(widget.transaction.id);
    Navigator.of(context).pop();
  }

  void _save() {
    final amount = double.tryParse(_amountController.text.trim());
    ref
        .read(pdfImportControllerProvider.notifier)
        .updateTransaction(
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
    final category = _categoryId == null
        ? null
        : categories.firstWhere((c) => c.id == _categoryId);
    final amount = double.tryParse(_amountController.text.trim());
    final chipColor = category != null
        ? Color(category.colorValue)
        : context.colors.primary;
    final amountColor = _type == TransactionType.income
        ? AppColors.income
        : AppColors.expense;
    final sign = _type == TransactionType.income ? '+' : '-';

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transaction Details',
                      style: context.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  FlowFiIconChip(
                    icon: category?.icon ?? Icons.category_outlined,
                    color: chipColor,
                    size: 48,
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _descriptionController.text.isEmpty
                              ? 'Unknown'
                              : _descriptionController.text,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${category?.name ?? 'Uncategorized'} · ${_date.shortDate}',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.flowfi.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Text(
                    amount == null
                        ? '—'
                        : '$sign${CurrencyFormatter.instance.format(amount)}',
                    style: context.textTheme.titleMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),
              Container(
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: context.colors.outlineVariant),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Description',
                      value: _descriptionController.text.isEmpty
                          ? 'Unknown'
                          : _descriptionController.text,
                      onTap: _editDescription,
                    ),
                    _DetailRow(
                      label: 'Category',
                      value: category?.name ?? 'Uncategorized',
                      onTap: _pickCategory,
                    ),
                    _DetailRow(
                      label: 'Amount',
                      value: amount == null
                          ? '—'
                          : CurrencyFormatter.instance.format(amount),
                      onTap: _editAmount,
                    ),
                    _DetailRow(
                      label: 'Type',
                      value: _type == TransactionType.income
                          ? 'Income'
                          : 'Expense',
                      onTap: _pickType,
                    ),
                    _DetailRow(
                      label: 'Date',
                      value: _date.fullDate,
                      onTap: _pickDate,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.expense,
                      ),
                      label: const Text(
                        'Delete',
                        style: TextStyle(color: AppColors.expense),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.expense),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "Label ... value ›" row in the details card — tapping it opens
/// whatever the underlying field needs (a dialog, a date picker, a bottom
/// sheet), keeping the actual edit affordance for each field.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.isLast = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.md,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: context.colors.outlineVariant),
                ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.flowfi.textTertiary,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                style: context.textTheme.bodyMedium,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSizes.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: AppSizes.iconSm,
              color: context.flowfi.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small dialog for editing a single text field (Description or Amount)
/// — used so tapping a detail row opens a focused editor for just that
/// field, instead of every field sharing one flat form.
class _TextFieldDialog extends StatefulWidget {
  const _TextFieldDialog({
    required this.title,
    required this.initialValue,
    required this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.prefixText,
  });

  final String title;
  final String initialValue;
  final TextInputType keyboardType;
  final TextCapitalization capitalization;
  final String? prefixText;

  @override
  State<_TextFieldDialog> createState() => _TextFieldDialogState();
}

class _TextFieldDialogState extends State<_TextFieldDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.capitalization,
        decoration: InputDecoration(
          isDense: true,
          prefixText: widget.prefixText,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A small bottom sheet for choosing Expense/Income — used when tapping the
/// "Type" detail row.
class _TypePickerSheet extends StatelessWidget {
  const _TypePickerSheet({required this.selected});
  final TransactionType selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          0,
          AppSizes.lg,
          AppSizes.lg,
        ),
        child: RadioGroup<TransactionType>(
          groupValue: selected,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final type in TransactionType.values)
                RadioListTile<TransactionType>(
                  value: type,
                  title: Text(
                    type == TransactionType.income ? 'Income' : 'Expense',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small bottom sheet for choosing a category — used when tapping the
/// "Category" detail row.
class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedId,
  });

  final List<Category> categories;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: RadioGroup<String>(
          groupValue: selectedId,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              0,
              AppSizes.lg,
              AppSizes.lg,
            ),
            children: [
              for (final category in categories)
                RadioListTile<String>(
                  value: category.id,
                  title: Text(category.name),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
