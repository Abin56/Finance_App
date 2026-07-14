import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/ledger_entry_type.dart';
import '../providers/people_providers.dart';

/// Soft-deleted ledger entries for one person, scoped by [personId].
/// Restore/permanent-delete go through [LedgerRepository]'s
/// person-aware methods so the balance stays correct.
class PersonLedgerTrashScreen extends ConsumerWidget {
  const PersonLedgerTrashScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(ledgerTrashStreamProvider(personId));
    final person = ref.watch(peopleStreamProvider).value?.where((p) => p.id == personId).firstOrNull;

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
              subtitle: 'Deleted entries will appear here until you restore or remove them.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: trashed.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final entry = trashed[index];
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                leading: Icon(entry.type.icon, color: entry.type.color),
                title: Text(entry.type.label),
                subtitle: Text(
                  '${CurrencyFormatter.instance.format(entry.amount)} · Deleted ${entry.deletedAt!.toLocal()}'
                      .split('.')
                      .first,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore_rounded),
                      tooltip: 'Restore',
                      onPressed: person == null
                          ? null
                          : () => ref.read(ledgerRepositoryProvider(personId)).restoreEntry(person, entry),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete forever',
                      onPressed: () => _confirmPermanentDelete(context, ref, entry),
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

  Future<void> _confirmPermanentDelete(BuildContext context, WidgetRef ref, LedgerEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This entry will be permanently removed. This can\'t be undone.'),
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
      await ref.read(ledgerRepositoryProvider(personId)).permanentlyDeleteEntry(entry);
    }
  }
}
