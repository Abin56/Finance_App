import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../data/expense_repository.dart';
import '../../domain/expense.dart';
import '../../domain/split_type.dart';
import '../providers/expense_providers.dart';

/// Figma "Edit Expense" (frame 3) — a Cancel/Save modal editing an existing
/// split/assigned expense's basic fields (title, amount, date, category,
/// note), with a Delete Expense button at the bottom. Deliberately does not
/// expose participant/share editing (that lives in [SplitExpenseFormSheet]);
/// when the amount changes on a split, each participant's share is rescaled
/// proportionally so the totals always reconcile — see [_save].
class EditExpenseSheet extends ConsumerStatefulWidget {
  const EditExpenseSheet({super.key, required this.expense});

  final Expense expense;

  /// Resolves to `true` when an edit was saved, `false` when the expense was
  /// deleted, and `null` when the user cancelled — so callers only show a
  /// success confirmation on an actual save.
  static Future<bool?> show(BuildContext context, {required Expense expense}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => EditExpenseSheet(expense: expense)),
    );
  }

  @override
  ConsumerState<EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends ConsumerState<EditExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.expense.description);
  late final _amountController = TextEditingController(text: widget.expense.totalAmount.toStringAsFixed(2));
  late final _noteController = TextEditingController(text: widget.expense.notes);
  late DateTime _date = widget.expense.date;
  late String _categoryId = widget.expense.categoryId;
  final _amountFocusNode = FocusNode();
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
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
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
          children: [
            for (final category in categories)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(category.colorValue).withValues(alpha: 0.15),
                  child: Icon(category.icon, color: Color(category.colorValue), size: AppSizes.iconSm),
                ),
                title: Text(category.name),
                trailing: category.id == _categoryId ? Icon(Icons.check_rounded, color: context.colors.primary) : null,
                onTap: () => Navigator.of(sheetContext).pop(category.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  /// Rebuilds participant inputs for a new total, keeping each person's
  /// relative portion — the last participant absorbs any rounding remainder
  /// so the custom split still sums exactly to [newTotal].
  List<ExpenseParticipantInput> _rescaledInputs(double newTotal) {
    final oldTotal = widget.expense.totalAmount;
    final participants = widget.expense.participants;
    final scaled = <double>[
      for (final p in participants) ((p.share / oldTotal * newTotal) * 100).round() / 100,
    ];
    final remainder = ((newTotal - scaled.fold(0.0, (s, v) => s + v)) * 100).round() / 100;
    if (scaled.isNotEmpty) scaled[scaled.length - 1] = ((scaled.last + remainder) * 100).round() / 100;
    return [
      for (var i = 0; i < participants.length; i++)
        ExpenseParticipantInput(
          personId: participants[i].personId,
          name: participants[i].name,
          value: scaled[i],
          isMe: participants[i].isMe,
        ),
    ];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(expenseRepositoryProvider);
      final scheduleId = widget.expense.scheduleId;
      final currentInstallments = scheduleId == null
          ? const <Installment>[]
          : ref.read(installmentsStreamProvider(scheduleId)).value ?? const <Installment>[];
      final newTotal = double.parse(_amountController.text.trim());
      final amountChanged = newTotal != widget.expense.totalAmount;

      await repository.editExpense(
        expense: widget.expense,
        currentInstallments: currentInstallments,
        description: _titleController.text.trim(),
        date: _date,
        categoryId: _categoryId,
        notes: _noteController.text.trim(),
        totalAmount: amountChanged ? newTotal : null,
        splitType: amountChanged && widget.expense.isSplit ? SplitType.custom : null,
        participantInputs: amountChanged && widget.expense.isSplit ? _rescaledInputs(newTotal) : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save expense: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(context, entityName: 'Expense');
    if (!confirmed || !mounted) return;
    try {
      await ref.read(expenseRepositoryProvider).deleteExpense(widget.expense);
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete expense: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.expense));
    final selectedCategory = categories.where((c) => c.id == _categoryId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        leadingWidth: 80,
        title: const Text('Edit Expense'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text('Save', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            Text('Title', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.xs),
            TextFormField(
              controller: _titleController,
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
              ),
              validator: Validators.required,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _amountFocusNode.requestFocus(),
            ),
            const SizedBox(height: AppSizes.md),
            Text('Amount', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.xs),
            TextFormField(
              controller: _amountController,
              focusNode: _amountFocusNode,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee_rounded)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.amount,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSizes.md),
            Text('Date', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.xs),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              child: InputDecorator(
                decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined)),
                child: Text(_date.fullDate),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text('Category', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.xs),
            InkWell(
              onTap: () => _pickCategory(categories),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              child: InputDecorator(
                decoration: const InputDecoration(),
                child: Row(
                  children: [
                    if (selectedCategory != null) ...[
                      Icon(selectedCategory.icon, color: Color(selectedCategory.colorValue), size: AppSizes.iconSm),
                      const SizedBox(width: AppSizes.sm),
                    ],
                    Expanded(child: Text(selectedCategory?.name ?? 'Select a category')),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text('Note (Optional)', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.xs),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(),
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSizes.xl),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(color: context.colors.error),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete Expense'),
            ),
          ],
        ),
      ),
    );
  }
}
