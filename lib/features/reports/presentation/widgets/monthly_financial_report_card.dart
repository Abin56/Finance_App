import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_report_providers.dart';
import '../../../cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../providers/monthly_financial_report_providers.dart';

/// The Monthly Financial Report — 20 line items covering income, expenses,
/// payments made/pending across every obligation type, receivables, credit
/// card standing, and charges, for the selected report period. Every value
/// composes an existing provider/model field; GST/IGST have no data source
/// anywhere in the app today and render as "Not Tracked Yet" rather than a
/// fabricated number.
class MonthlyFinancialReportCard extends ConsumerWidget {
  const MonthlyFinancialReportCard({
    super.key,
    required this.periodStart,
    required this.periodEnd,
    required this.income,
    required this.expenses,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final double income;
  final double expenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = (start: periodStart, end: periodEnd);

    final billsPaid = ref.watch(billsPaidForRangeProvider(range));
    final emiPaid = ref.watch(emiPaidForRangeProvider(range));
    final loanPaid = ref.watch(loanPaidForRangeProvider(range));
    final creditCardBillsPaid = ref.watch(creditCardBillsPaidForRangeProvider(range));
    final pendingBills =
        ref.watch(overdueBillsProvider).fold(0.0, (sum, b) => sum + b.remainingAmount) +
            ref.watch(upcomingBillsProvider).fold(0.0, (sum, b) => sum + b.remainingAmount);
    final pendingEmi = ref.watch(totalRemainingEmiBalanceProvider);
    final pendingLoans = ref.watch(totalAmountToReceiveProvider);
    final moneyToReceive = ref.watch(totalMoneyToReceiveProvider);
    final moneyCollected = ref.watch(moneyReceivedForRangeProvider(range));
    final ccOutstanding = ref.watch(totalCreditCardOutstandingProvider);
    final utilization = ref.watch(creditUtilizationPercentProvider);
    final interestPaid = ref.watch(interestChargedForRangeProvider(range));
    final insuranceCharges = ref.watch(insuranceChargesForRangeProvider(range));
    final processingFees = ref.watch(processingFeesForRangeProvider(range));
    final penalties = ref.watch(lateFeesForRangeProvider(range));
    final otherCharges = ref.watch(otherChargesForRangeProvider(range));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly Financial Report', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.lg),
          _ReportRow('Total Income', income),
          _ReportRow('Total Expenses', expenses),
          _ReportRow('Total Bills Paid', billsPaid),
          _ReportRow('Total EMI Paid', emiPaid),
          _ReportRow('Total Loan Payments', loanPaid),
          _ReportRow('Credit Card Bills Paid', creditCardBillsPaid),
          _ReportRow('Pending Bills', pendingBills),
          _ReportRow('Pending EMI', pendingEmi),
          _ReportRow('Pending Loans', pendingLoans),
          _ReportRow('Money To Receive', moneyToReceive),
          _ReportRow('Money Collected', moneyCollected),
          _ReportRow('Credit Card Outstanding', ccOutstanding),
          _ReportRow('Credit Utilization %', utilization, isPercent: true),
          _ReportRow('Interest Paid', interestPaid),
          const _NotTrackedRow('GST Paid'),
          const _NotTrackedRow('IGST Paid'),
          _ReportRow('Insurance Charges', insuranceCharges),
          _ReportRow('Processing Fees', processingFees),
          _ReportRow('Penalties', penalties),
          _ReportRow('Other Charges', otherCharges),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow(this.label, this.value, {this.isPercent = false});

  final String label;
  final double value;
  final bool isPercent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textTheme.bodyMedium)),
          Text(
            isPercent ? '${value.toStringAsFixed(1)}%' : CurrencyFormatter.instance.format(value),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _NotTrackedRow extends StatelessWidget {
  const _NotTrackedRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
            ),
          ),
          Text(
            'Not Tracked Yet',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
