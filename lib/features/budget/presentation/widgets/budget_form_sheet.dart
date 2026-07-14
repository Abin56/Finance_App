import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/budget.dart';
import '../../domain/budget_type.dart';
import '../providers/budget_providers.dart';

/// Bottom sheet for creating or editing a budget. [type] and [categoryId]
/// are fixed by which entry point opened the sheet (daily card, monthly
/// card, or "add category budget") — only the amount is user-editable,
/// matching [Budget]'s own create/edit-time immutability rules.
class BudgetFormSheet extends ConsumerStatefulWidget {
  const BudgetFormSheet({
    super.key,
    required this.type,
    this.categoryId,
    this.categoryName,
    this.budget,
  });

  final BudgetType type;
  final String? categoryId;
  final String? categoryName;
  final Budget? budget;

  static Future<void> show(
    BuildContext context, {
    required BudgetType type,
    String? categoryId,
    String? categoryName,
    Budget? budget,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => BudgetFormSheet(
        type: type,
        categoryId: categoryId,
        categoryName: categoryName,
        budget: budget,
      ),
    );
  }

  @override
  ConsumerState<BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<BudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: widget.budget == null ? '' : widget.budget!.amount.toStringAsFixed(2),
  );
  bool _isSaving = false;

  bool get _isEditing => widget.budget != null;

  String get _title {
    if (widget.categoryId != null) {
      return _isEditing
          ? 'Edit ${widget.categoryName ?? 'category'} budget'
          : 'Set ${widget.categoryName ?? 'category'} budget';
    }
    return _isEditing ? 'Edit ${widget.type.label.toLowerCase()} budget' : 'Set ${widget.type.label.toLowerCase()} budget';
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(budgetRepositoryProvider);
      final amount = double.parse(_amountController.text.trim());

      if (_isEditing) {
        await repository.editBudget(widget.budget!, amount: amount);
      } else {
        await repository.createBudget(
          type: widget.type,
          amount: amount,
          categoryId: widget.categoryId,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save budget: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSizes.lg),
            TextFormField(
              controller: _amountController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.amount,
            ),
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(
              label: _isEditing ? 'Save changes' : 'Set budget',
              isLoading: _isSaving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }
}
