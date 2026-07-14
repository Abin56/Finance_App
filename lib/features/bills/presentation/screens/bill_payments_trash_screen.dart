import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/payment_record.dart';
import '../providers/bill_providers.dart';

/// Soft-deleted payments for one bill, scoped by [billId]. Restore/
/// permanent-delete go through [PaymentRepository]'s bill-aware methods
/// so [Bill.amountPaid] stays correct — mirrors [PersonLedgerTrashScreen].
class BillPaymentsTrashScreen extends ConsumerWidget {
  const BillPaymentsTrashScreen({super.key, required this.billId});

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(paymentsTrashStreamProvider(billId));
    final bill = ref.watch(billsStreamProvider).value?.where((b) => b.id == billId).firstOrNull;

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
              subtitle: 'Deleted payments will appear here until you restore or remove them.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: trashed.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final payment = trashed[index];
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                title: Text(CurrencyFormatter.instance.format(payment.amount)),
                subtitle: Text(
                  'Deleted ${payment.deletedAt!.toLocal()}'.split('.').first,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore_rounded),
                      tooltip: 'Restore',
                      onPressed: bill == null
                          ? null
                          : () => ref.read(paymentRepositoryProvider(billId)).restorePayment(bill, payment),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete forever',
                      onPressed: () => _confirmPermanentDelete(context, ref, payment),
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

  Future<void> _confirmPermanentDelete(BuildContext context, WidgetRef ref, PaymentRecord payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This payment will be permanently removed. This can\'t be undone.'),
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
      await ref.read(paymentRepositoryProvider(billId)).permanentlyDeletePayment(payment);
    }
  }
}
