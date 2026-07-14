import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/savings_goal.dart';
import '../providers/savings_providers.dart';

/// Bottom sheet for creating or editing a savings goal. Contribution
/// amounts aren't entered here — see the tile's dedicated "Contribute"
/// action — this sheet only edits the goal's own fields.
class SavingsGoalFormSheet extends ConsumerStatefulWidget {
  const SavingsGoalFormSheet({super.key, this.goal});

  final SavingsGoal? goal;

  static Future<void> show(BuildContext context, {SavingsGoal? goal}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SavingsGoalFormSheet(goal: goal),
    );
  }

  @override
  ConsumerState<SavingsGoalFormSheet> createState() => _SavingsGoalFormSheetState();
}

class _SavingsGoalFormSheetState extends ConsumerState<SavingsGoalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.goal?.name);
  late final _targetController = TextEditingController(
    text: widget.goal == null ? '' : widget.goal!.targetAmount.toStringAsFixed(2),
  );
  late final _notesController = TextEditingController(text: widget.goal?.notes ?? '');
  DateTime? _dueDate;
  bool _isSaving = false;

  bool get _isEditing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.goal?.dueDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(savingsRepositoryProvider);
      final name = _nameController.text.trim();
      final target = double.parse(_targetController.text.trim());
      final notes = _notesController.text.trim();

      if (_isEditing) {
        await repository.editGoal(
          widget.goal!,
          name: name,
          targetAmount: target,
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          notes: notes,
        );
      } else {
        await repository.createGoal(name: name, targetAmount: target, dueDate: _dueDate, notes: notes);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save goal: $e')),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'Edit savings goal' : 'Add savings goal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Goal name'),
                validator: Validators.required,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _targetController,
                decoration: const InputDecoration(labelText: 'Target amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDueDate,
                      icon: const Icon(Icons.event_outlined, size: AppSizes.iconSm),
                      label: Text(_dueDate == null ? 'Due date (optional)' : _dueDate!.fullDate),
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Clear due date',
                      onPressed: () => setState(() => _dueDate = null),
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
                label: _isEditing ? 'Save changes' : 'Add goal',
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
