import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../providers/emi_report_providers.dart';

/// EMI section of the Reports screen — six stats, same visual pattern as
/// `DashboardLendingCard`'s stat grid.
class EmiReportSection extends ConsumerWidget {
  const EmiReportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalPaid = ref.watch(totalEmiPaidProvider);
    final remaining = ref.watch(remainingEmiProvider);
    final interestPaid = ref.watch(interestPaidProvider);
    final principalPaid = ref.watch(principalPaidProvider);
    final upcoming = ref.watch(upcomingEmiCountProvider);
    final overdue = ref.watch(overdueEmiReportCountProvider);
    final overdueAmount = ref.watch(overdueEmiAmountProvider);
    final totalEmis = ref.watch(totalEmisCountProvider);
    final closedEmis = ref.watch(closedEmisCountProvider);
    final gstPaid = ref.watch(totalGstPaidProvider);
    final igstPaid = ref.watch(totalIgstPaidProvider);
    final insurancePaid = ref.watch(totalInsuranceChargePaidProvider);
    final processingFeesPaid = ref.watch(totalProcessingFeePaidProvider);
    final penaltiesPaid = ref.watch(totalPenaltyPaidProvider);
    final otherChargesPaid = ref.watch(totalOtherChargesPaidProvider);
    final overallPaid = ref.watch(overallAmountPaidProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'EMI'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _ReportStat(label: 'Total EMIs', value: '$totalEmis')),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(child: _ReportStat(label: 'Closed EMIs', value: '$closedEmis')),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(child: _ReportStat(label: 'Total paid', value: CurrencyFormatter.instance.format(totalPaid))),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(child: _ReportStat(label: 'Amount Left', value: CurrencyFormatter.instance.format(remaining))),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(
                    child: _ReportStat(label: 'Interest paid', value: CurrencyFormatter.instance.format(interestPaid)),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: _ReportStat(
                      label: 'Loan amount paid',
                      value: CurrencyFormatter.instance.format(principalPaid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(child: _ReportStat(label: 'Upcoming Monthly EMI', value: '$upcoming')),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(child: _ReportStat(label: 'Missed Payment EMI', value: '$overdue')),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              _ReportStat(label: 'Amount Left (Missed)', value: CurrencyFormatter.instance.format(overdueAmount)),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        const SectionHeader(title: 'EMI Charges'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ReportStat(
                      label: 'Principal Paid',
                      value: CurrencyFormatter.instance.format(principalPaid),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: _ReportStat(
                      label: 'Interest Paid',
                      value: CurrencyFormatter.instance.format(interestPaid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(child: _ReportStat(label: 'GST Paid', value: CurrencyFormatter.instance.format(gstPaid))),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(child: _ReportStat(label: 'IGST Paid', value: CurrencyFormatter.instance.format(igstPaid))),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(
                    child: _ReportStat(label: 'Insurance Paid', value: CurrencyFormatter.instance.format(insurancePaid)),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: _ReportStat(
                      label: 'Processing Fees',
                      value: CurrencyFormatter.instance.format(processingFeesPaid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(
                    child: _ReportStat(label: 'Penalties', value: CurrencyFormatter.instance.format(penaltiesPaid)),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: _ReportStat(
                      label: 'Other Charges',
                      value: CurrencyFormatter.instance.format(otherChargesPaid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              _ReportStat(label: 'Total EMI Paid', value: CurrencyFormatter.instance.format(overallPaid)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
