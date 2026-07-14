import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../domain/budget.dart';
import '../../domain/budget_type.dart';
import '../providers/budget_providers.dart';

/// Soft-deleted budgets awaiting restore or permanent deletion.
class BudgetTrashScreen extends ConsumerWidget {
  const BudgetTrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(budgetsTrashStreamProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};

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
              subtitle: 'Deleted budgets will appear here until you restore or remove them.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: trashed.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final budget = trashed[index];
              final categoryName = budget.categoryId == null
                  ? '${budget.type.label} budget'
                  : categoriesById[budget.categoryId]?.name ?? 'Category budget';
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                title: Text(categoryName),
                subtitle: Text(
                  '${CurrencyFormatter.instance.format(budget.amount)} · Deleted ${budget.deletedAt!.toLocal()}'
                      .split('.')
                      .first,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore_rounded),
                      tooltip: 'Restore',
                      onPressed: () => ref.read(budgetRepositoryProvider).restore(budget),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete forever',
                      onPressed: () => _confirmPermanentDelete(context, ref, budget),
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

  Future<void> _confirmPermanentDelete(BuildContext context, WidgetRef ref, Budget budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This budget will be permanently removed. This can\'t be undone.'),
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
      await ref.read(budgetRepositoryProvider).permanentlyDelete(budget);
    }
  }
}
