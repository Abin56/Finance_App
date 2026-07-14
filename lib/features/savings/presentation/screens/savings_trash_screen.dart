import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/savings_goal.dart';
import '../providers/savings_providers.dart';

/// Soft-deleted savings goals awaiting restore or permanent deletion.
class SavingsTrashScreen extends ConsumerWidget {
  const SavingsTrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(savingsTrashStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (trashed) {
          if (trashed.isEmpty) {
            return const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is empty',
              subtitle: 'Deleted goals will appear here until you restore or remove them.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: trashed.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final goal = trashed[index];
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                title: Text(goal.name),
                subtitle: Text(
                  '${CurrencyFormatter.instance.format(goal.currentAmount)} of ${CurrencyFormatter.instance.format(goal.targetAmount)} · Deleted ${goal.deletedAt!.toLocal()}'
                      .split('.')
                      .first,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore_rounded),
                      tooltip: 'Restore',
                      onPressed: () => ref.read(savingsRepositoryProvider).restore(goal),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete forever',
                      onPressed: () => _confirmPermanentDelete(context, ref, goal),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmPermanentDelete(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: Text('"${goal.name}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(savingsRepositoryProvider).permanentlyDelete(goal);
    }
  }
}
