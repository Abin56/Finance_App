import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/bill.dart';
import '../../domain/bill_recurrence.dart';
import '../../domain/bill_status.dart';
import '../../domain/payment_record.dart';
import '../providers/bill_providers.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/payment_form_sheet.dart';
import '../widgets/payment_tile.dart';
import 'bill_payments_trash_screen.dart';

/// One bill's full detail — status, progress, and its payment history,
/// mirrors [PersonStatementScreen].
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key, required this.billId});

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(billsStreamProvider);
    final bill = billsAsync.value?.where((b) => b.id == billId).firstOrNull;
    final paymentsAsync = ref.watch(paymentsStreamProvider(billId));

    return Scaffold(
      appBar: AppBar(
        title: Text(bill?.name ?? 'Bill'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BillPaymentsTrashScreen(billId: billId)),
            ),
          ),
          if (bill != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit bill',
              onPressed: () => BillFormSheet.show(context, bill: bill),
            ),
        ],
      ),
      floatingActionButton: bill == null
          ? null
          : FloatingActionButton(
              heroTag: 'bill_detail_fab',
              onPressed: () => PaymentFormSheet.show(context, bill),
              child: const Icon(Icons.add),
            ),
      body: bill == null
          ? const Center(child: CircularProgressIndicator())
          : paymentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Something went wrong: $error')),
              data: (payments) {
                final sorted = [...payments]..sort((a, b) => b.date.compareTo(a.date));

                return ListView(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  children: [
                    _BillSummaryCard(bill: bill),
                    const SizedBox(height: AppSizes.lg),
                    Text('Payment Records', style: context.textTheme.titleMedium),
                    const SizedBox(height: AppSizes.sm),
                    if (sorted.isEmpty)
                      const EmptyState(
                        icon: Icons.payments_outlined,
                        title: 'No payments yet',
                        subtitle: 'Record a payment to track progress toward this bill.',
                      )
                    else
                      for (final payment in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSizes.sm),
                          child: Dismissible(
                            key: ValueKey(payment.id),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => confirmDelete(context, entityName: 'Payment'),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                              decoration: BoxDecoration(
                                color: context.colors.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                              ),
                              child: Icon(Icons.delete_outline_rounded, color: context.colors.error),
                            ),
                            onDismissed: (_) => _softDeleteWithUndo(context, ref, bill, payment),
                            child: PaymentTile(payment: payment, onTap: () {}),
                          ),
                        ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _softDeleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    Bill bill,
    PaymentRecord payment,
  ) async {
    final repository = ref.read(paymentRepositoryProvider(billId));
    await repository.softDeletePayment(bill, payment);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Payment moved to trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.restorePayment(bill, payment),
        ),
      ),
    );
  }
}

class _BillSummaryCard extends ConsumerWidget {
  const _BillSummaryCard({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = bill.status;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Due ${bill.dueDate.fullDate}', style: context.textTheme.bodyMedium),
              Row(
                children: [
                  Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                  const SizedBox(width: AppSizes.xs),
                  Text(status.label, style: context.textTheme.bodyMedium?.copyWith(color: status.color)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            '${CurrencyFormatter.instance.format(bill.amountPaid)} of ${CurrencyFormatter.instance.format(bill.amount)}',
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.sm),
          ProgressBar(progress: bill.amount == 0 ? 0 : bill.amountPaid / bill.amount),
          if (bill.recurrence.name != 'oneTime') ...[
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                Icon(Icons.repeat_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: AppSizes.xs),
                Text(
                  'Repeats ${bill.recurrence.label.toLowerCase()}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
          if (bill.notes.isNotEmpty) ...[
            const SizedBox(height: AppSizes.md),
            Text(bill.notes, style: context.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
