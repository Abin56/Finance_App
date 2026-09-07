import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan.dart';
import 'record_loan_payment_sheet.dart';

/// Read-only detail view for a single [Installment] — due/paid/remaining
/// amounts, principal/interest split (when present), status, and the full
/// payment history for this installment. Offers a "Make Payment" action when
/// the installment isn't fully paid, which hands off to
/// [RecordLoanPaymentSheet]. Never mutates or recomputes anything itself —
/// every figure comes straight from the [Installment]/[InstallmentPayment]
/// models already in hand.
class LoanInstallmentDetailSheet extends ConsumerWidget {
  const LoanInstallmentDetailSheet({super.key, required this.installment, this.loan});

  final Installment installment;
  final Loan? loan;

  static Future<void> show(BuildContext context, Installment installment, {Loan? loan}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => LoanInstallmentDetailSheet(installment: installment, loan: loan),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = installment.status;
    final paymentsAsync = ref.watch(
      installmentPaymentsStreamProvider((scheduleId: installment.scheduleId, installmentId: installment.id)),
    );
    final people = ref.watch(peopleStreamProvider).value ?? const [];

    return SectionedFormSheet(
      title: 'Payment ${installment.sequenceNumber}',
      description: installment.dueDate.fullDate,
      showConfirm: false,
      onConfirm: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Details'),
          const SizedBox(height: AppSizes.sm),
          _DetailRow(label: 'Due', value: CurrencyFormatter.instance.format(installment.amountDue)),
          _DetailRow(label: 'Paid', value: CurrencyFormatter.instance.format(installment.amountPaid)),
          _DetailRow(label: 'Remaining', value: CurrencyFormatter.instance.format(installment.remainingAmount)),
          if (installment.principalPortion != null)
            _DetailRow(label: 'Principal', value: CurrencyFormatter.instance.format(installment.principalPortion!)),
          if (installment.interestPortion != null)
            _DetailRow(label: 'Interest', value: CurrencyFormatter.instance.format(installment.interestPortion!)),
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.xs),
            child: Row(
              children: [
                Text('Status', style: context.textTheme.bodyMedium),
                const Spacer(),
                Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                const SizedBox(width: AppSizes.xs),
                Text(status.label, style: context.textTheme.bodyMedium?.copyWith(color: status.color)),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          const SectionLabel('Payment History'),
          const SizedBox(height: AppSizes.sm),
          paymentsAsync.when(
            data: (payments) {
              if (payments.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                  child: Text(
                    'No payments recorded yet.',
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                  ),
                );
              }
              final sorted = [...payments]..sort((a, b) => b.date.compareTo(a.date));
              return Column(
                children: [
                  for (final payment in sorted) _PaymentHistoryRow(payment: payment, people: people),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSizes.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              'Could not load payment history: $e',
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.error),
            ),
          ),
          if (installment.remainingAmount > 0) ...[
            const SizedBox(height: AppSizes.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  RecordLoanPaymentSheet.show(context, installment, loan: loan);
                },
                child: const Text('Make Payment'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: context.textTheme.bodyMedium),
          const Spacer(),
          Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PaymentHistoryRow extends StatelessWidget {
  const _PaymentHistoryRow({required this.payment, required this.people});

  final InstallmentPayment payment;
  final List<dynamic> people;

  @override
  Widget build(BuildContext context) {
    String payerLabel;
    if (payment.payerPersonId == null) {
      payerLabel = 'Paid by You';
    } else {
      final match = people.where((p) => p.id == payment.payerPersonId);
      payerLabel = match.isNotEmpty ? 'Paid by ${match.first.name}' : 'Paid by You';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(payment.date.shortDate, style: context.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              payerLabel,
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          Text(
            CurrencyFormatter.instance.format(payment.amount),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
