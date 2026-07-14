import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../domain/savings_goal.dart';
import '../providers/savings_providers.dart';
import 'savings_goal_form_sheet.dart';

/// One row for a savings goal — progress, percentage, due date (with
/// relative phrasing), a completed badge, and Contribute/Archive/Complete
/// actions kept on the row rather than a separate detail screen.
class SavingsGoalTile extends ConsumerWidget {
  const SavingsGoalTile({super.key, required this.goal});

  final SavingsGoal goal;

  String? get _dueDateLabel {
    final due = goal.dueDate;
    if (due == null) return null;
    final days = due.difference(DateTime.now()).inDays;
    if (days < 0) return 'Missed Payment';
    if (days == 0) return 'To Pay today';
    return 'To Pay in $days day${days == 1 ? '' : 's'}';
  }

  Future<void> _showContributeDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add contribution'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Amount'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: Validators.amount,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(double.parse(controller.text.trim()));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (amount == null || !context.mounted) return;
    try {
      await ref.read(savingsRepositoryProvider).contribute(goal, amount);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add contribution: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(savingsRepositoryProvider);
    final dueDateLabel = _dueDateLabel;
    final overdue = dueDateLabel == 'Missed Payment';

    return AppCard(
      onTap: () => SavingsGoalFormSheet.show(context, goal: goal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: goal.isCompleted ? context.colors.onSurface.withValues(alpha: 0.5) : null,
                  ),
                ),
              ),
              if (goal.isCompleted)
                Icon(Icons.check_circle_rounded, color: AppColors.income, size: AppSizes.iconSm),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) async {
                  switch (action) {
                    case 'contribute':
                      await _showContributeDialog(context, ref);
                    case 'complete':
                      await repository.markCompleted(goal);
                    case 'incomplete':
                      await repository.markIncomplete(goal);
                    case 'archive':
                      await repository.archive(goal);
                    case 'unarchive':
                      await repository.unarchive(goal);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'contribute', child: Text('Add contribution')),
                  if (!goal.isCompleted)
                    const PopupMenuItem(value: 'complete', child: Text('Mark completed')),
                  if (goal.isCompleted)
                    const PopupMenuItem(value: 'incomplete', child: Text('Mark incomplete')),
                  if (!goal.isArchived)
                    const PopupMenuItem(value: 'archive', child: Text('Archive')),
                  if (goal.isArchived)
                    const PopupMenuItem(value: 'unarchive', child: Text('Unarchive')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          ProgressBar(
            progress: goal.progress,
            label:
                '${CurrencyFormatter.instance.format(goal.currentAmount)} of ${CurrencyFormatter.instance.format(goal.targetAmount)} · ${goal.progress.asPercent}',
          ),
          if (dueDateLabel != null) ...[
            const SizedBox(height: AppSizes.sm),
            Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: AppSizes.iconSm,
                  color: overdue ? AppColors.error : context.colors.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: AppSizes.xs),
                Text(
                  dueDateLabel,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: overdue ? AppColors.error : context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
