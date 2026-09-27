import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/loan.dart';
import '../providers/loan_providers.dart';
import '../widgets/reverse_origination_dialog.dart';

/// Soft-deleted loans awaiting restore or permanent deletion.
class LoansTrashScreen extends ConsumerWidget {
  const LoansTrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(loansTrashStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: SafeArea(
        child: trashAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Something went wrong: $error')),
          data: (trashed) {
            if (trashed.isEmpty) {
              return const EmptyState(
                icon: Icons.delete_outline_rounded,
                title: 'Trash is empty',
                subtitle:
                    'Deleted loans will appear here until you restore or remove them.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(AppSizes.lg),
              itemCount: trashed.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
              itemBuilder: (context, index) {
                final loan = trashed[index];
                return ListTile(
                  tileColor: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  ),
                  title: Text(
                    loan.name?.isNotEmpty == true ? loan.name! : 'Loan',
                  ),
                  subtitle: Text(
                    'Deleted ${loan.deletedAt!.toLocal()}'.split('.').first,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore_rounded),
                        tooltip: 'Restore',
                        onPressed: () async {
                          try {
                            await ref
                                .read(loanRepositoryProvider)
                                .restore(loan);
                          } on AppException catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.message)),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_forever_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        tooltip: 'Delete forever',
                        onPressed: () =>
                            _confirmPermanentDelete(context, ref, loan),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmPermanentDelete(
    BuildContext context,
    WidgetRef ref,
    Loan loan,
  ) async {
    // Trashed (e.g. by an older app) while its origination money was still
    // active: reverse it instead — never hard-delete it out from under its
    // Transaction.
    if (await reverseOriginationIfMoneyActive(context, ref, loan)) return;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text(
          'This loan and its history will be permanently removed. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(loanRepositoryProvider).permanentlyDeleteLoan(loan);
    }
  }
}
