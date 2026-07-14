import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../providers/savings_providers.dart';
import '../widgets/savings_goal_form_sheet.dart';
import '../widgets/savings_goal_tile.dart';
import 'savings_trash_screen.dart';

/// Active savings goals, an archived-goals toggle, and a trash entry
/// point — everything reachable from one list, consistent with
/// Accounts/Categories/Budget.
class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final activeGoals = ref.watch(activeSavingsGoalsProvider);
    final archivedGoals = ref.watch(archivedSavingsGoalsProvider);
    final goalsAsync = ref.watch(savingsGoalsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavingsTrashScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'savings_fab',
        onPressed: () => SavingsGoalFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (goals) {
          if (goals.isEmpty) {
            return EmptyState(
              icon: Icons.savings_outlined,
              title: 'No savings goals yet',
              subtitle: 'Create a goal to start tracking your progress.',
              action: FilledButton(
                onPressed: () => SavingsGoalFormSheet.show(context),
                child: const Text('Add your first goal'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              if (activeGoals.isEmpty)
                const EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'No active goals',
                  subtitle: 'All your goals are archived.',
                )
              else
                for (final goal in activeGoals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: SavingsGoalTile(goal: goal),
                  ),
              if (archivedGoals.isNotEmpty) ...[
                const SizedBox(height: AppSizes.md),
                SectionHeader(
                  title: 'Archived (${archivedGoals.length})',
                  actionLabel: _showArchived ? 'Hide' : 'Show',
                  onActionTap: () => setState(() => _showArchived = !_showArchived),
                ),
                if (_showArchived)
                  for (final goal in archivedGoals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: SavingsGoalTile(goal: goal),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }
}
