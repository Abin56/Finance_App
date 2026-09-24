import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan_category.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_repayment_type.dart';
import '../../domain/loan_status.dart';
import '../providers/loan_providers.dart';
import '../widgets/loan_category_badge.dart';
import '../widgets/loan_direction_badge.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/loan_installment_detail_sheet.dart';
import '../widgets/loan_installment_tile.dart';
import '../widgets/loan_interest_breakdown_card.dart';
import '../widgets/loan_payment_detail_sheet.dart';
import '../widgets/loan_payment_history_tile.dart';
import '../widgets/loan_timeline_tile.dart';
import '../widgets/record_loan_lump_sum_settlement_sheet.dart';
import '../widgets/record_loan_payment_sheet.dart';

/// One loan's overview dashboard — status/header, financial summary,
/// progress, next payment / overdue callouts, loan information, default
/// payer, quick actions, and the full installment schedule. All numbers come
/// from `LoanFinancialSummary` (via `loanFinancialSummaryProvider`) or direct
/// model fields — no calculation is duplicated here.
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansStreamProvider).value ?? const [];
    final loan = loans.where((l) => l.id == loanId).firstOrNull;

    if (loan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final person = people.where((p) => p.id == loan.personId).firstOrNull;
    final payer = loan.payerPersonId == null
        ? null
        : people.where((p) => p.id == loan.payerPersonId).firstOrNull;
    final installmentsAsync = ref.watch(installmentsStreamProvider(loan.scheduleId));
    final status = ref.watch(loanStatusProvider(loan));
    final summary = ref.watch(loanFinancialSummaryProvider(loan));
    final repository = ref.watch(loanRepositoryProvider);
    final cycleView = ref.watch(loanCycleViewRecordProvider(loan));
    final paymentHistory = ref.watch(loanPaymentHistoryProvider(loan));
    final timeline = ref.watch(loanTimelineProvider(loan));

    final isGiven = loan.direction == LoanDirection.given;
    final isInstitutional = loan.category == LoanCategory.institutional;
    final isInstallment = loan.repaymentType == LoanRepaymentType.installment;
    final isClosed = status == LoanStatus.closed;
    final counterpartyName = isInstitutional ? (loan.institutionName ?? 'Institution') : (person?.name ?? 'unknown');
    final defaultTitle = isGiven ? 'Loan to $counterpartyName' : 'Loan from $counterpartyName';

    return Scaffold(
      appBar: AppBar(
        title: Text(loan.name?.isNotEmpty == true ? loan.name! : defaultTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit loan',
            onPressed: () => LoanFormSheet.show(context, loan: loan),
          ),
          IconButton(
            icon: Icon(isClosed ? Icons.lock_open_rounded : Icons.check_circle_outline_rounded),
            tooltip: isClosed ? 'Reopen loan' : 'Close loan',
            onPressed: () async {
              if (loan.isClosed) {
                await repository.reopenLoan(loan, currentInstallments: installmentsAsync.value ?? const []);
              } else {
                await repository.closeLoan(loan);
              }
            },
          ),
        ],
      ),
      body: SafeArea(child: installmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (installments) {
          final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              // 1. Header: badges + status.
              Row(
                children: [
                  LoanDirectionBadge(direction: loan.direction),
                  const SizedBox(width: AppSizes.xs),
                  LoanCategoryBadge(category: loan.category),
                  const Spacer(),
                  Chip(
                    avatar: Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                    label: Text(status.label),
                    labelStyle: context.textTheme.bodySmall?.copyWith(color: status.color, fontWeight: FontWeight.w700),
                    backgroundColor: status.color.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (isInstitutional && loan.loanType?.isNotEmpty == true) ...[
                const SizedBox(height: AppSizes.xs),
                Text(
                  loan.loanType!,
                  style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                ),
              ],
              const SizedBox(height: AppSizes.lg),

              // 2. Financial summary card.
              Text('Financial Summary', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statRow(context, 'Original amount', loan.loanAmount),
                    _statRow(context, 'Total payable', summary.totalScheduledPayable),
                    _statRow(context, 'Total paid', summary.totalPaid),
                    _statRow(context, 'Outstanding', summary.outstanding, emphasize: true),
                    if (loan.interest != null) ...[
                      const Divider(height: AppSizes.xl),
                      _statRow(context, 'Principal remaining', summary.principalRemaining),
                      _statRow(context, 'Interest remaining', summary.interestRemaining),
                    ],
                    const SizedBox(height: AppSizes.md),
                    ProgressBar(
                      progress: summary.progress,
                      label:
                          '${CurrencyFormatter.instance.format(summary.totalPaid)} / ${CurrencyFormatter.instance.format(summary.totalScheduledPayable)} paid',
                    ),
                  ],
                ),
              ),

              // 2b. Interest breakdown / amortization — only for
              // interest-bearing installment loans (an interest-free or
              // full/single-payment loan has no per-installment breakdown to
              // show).
              if (loan.interest != null && isInstallment && sorted.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                LoanInterestBreakdownCard(loan: loan, installments: sorted, summary: summary),
              ],

              // 3. Overdue callout.
              if (summary.overdueInstallments > 0) ...[
                const SizedBox(height: AppSizes.lg),
                AppCard(
                  color: AppColors.error.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${summary.overdueInstallments} overdue payment${summary.overdueInstallments == 1 ? '' : 's'}',
                              style: context.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              CurrencyFormatter.instance.format(summary.overdueAmount),
                              style: context.textTheme.bodySmall?.copyWith(color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 4. Next payment card.
              if (summary.nextInstallment != null) ...[
                const SizedBox(height: AppSizes.lg),
                _buildNextPaymentCard(context, summary.nextInstallment!),
              ],

              // 6. Loan information.
              const SizedBox(height: AppSizes.lg),
              Text('Loan Information', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow(context, 'Loan amount', CurrencyFormatter.instance.format(loan.loanAmount)),
                    _detailRow(context, 'Loan date', loan.loanDate.fullDate),
                    if (loan.interest != null) ...[
                      _detailRow(context, 'Interest type', loan.interest!.type.label),
                      _detailRow(
                        context,
                        'Interest rate',
                        '${loan.interest!.ratePercent}% ${loan.interest!.period.label}',
                      ),
                    ],
                    _detailRow(context, 'Repayment type', loan.repaymentType.label),
                    if (isInstallment) ...[
                      if (loan.installmentFrequency != null)
                        _detailRow(context, 'Frequency', loan.installmentFrequency!.label),
                      if (loan.installmentCount != null)
                        _detailRow(context, 'Installments', '${loan.installmentCount}'),
                    ] else if (loan.dueDate != null)
                      _detailRow(context, 'Due date', loan.dueDate!.fullDate),
                    // 7. Payer.
                    const Divider(height: AppSizes.xl),
                    _detailRow(context, 'Default EMI payer', payer?.name ?? 'You'),
                  ],
                ),
              ),

              if (isInstitutional) ...[
                const SizedBox(height: AppSizes.lg),
                Text('Institution Details', style: context.textTheme.titleMedium),
                const SizedBox(height: AppSizes.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (loan.institutionName?.isNotEmpty == true)
                        _detailRow(context, 'Institution', loan.institutionName!),
                      if (loan.loanType?.isNotEmpty == true) _detailRow(context, 'Loan type', loan.loanType!),
                      if (loan.loanNumber?.isNotEmpty == true) _detailRow(context, 'Loan number', loan.loanNumber!),
                      if (loan.accountNumber?.isNotEmpty == true)
                        _detailRow(context, 'Account number', loan.accountNumber!),
                      if (loan.branch?.isNotEmpty == true) _detailRow(context, 'Branch', loan.branch!),
                    ],
                  ),
                ),
              ],

              // 8. Actions.
              const SizedBox(height: AppSizes.lg),
              Wrap(
                spacing: AppSizes.sm,
                runSpacing: AppSizes.sm,
                children: [
                  if (!isClosed && summary.outstanding > 0 && summary.nextInstallment != null)
                    FilledButton.icon(
                      onPressed: () => RecordLoanPaymentSheet.show(context, summary.nextInstallment!, loan: loan),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Pay'),
                    ),
                  if (!isClosed && summary.outstanding > 0)
                    OutlinedButton.icon(
                      onPressed: () => RecordLoanLumpSumSettlementSheet.show(context, loan),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('Settle'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => LoanFormSheet.show(context, loan: loan),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (loan.isClosed) {
                        await repository.reopenLoan(loan);
                      } else {
                        await repository.closeLoan(loan);
                      }
                    },
                    icon: Icon(isClosed ? Icons.lock_open_rounded : Icons.check_circle_outline_rounded),
                    label: Text(isClosed ? 'Reopen' : 'Close'),
                  ),
                ],
              ),

              // 9. Previous cycle pending + schedule (unchanged behavior).
              if (cycleView.previousCyclePending.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                Text('Previous Cycle Pending', style: context.textTheme.titleMedium),
                const SizedBox(height: AppSizes.sm),
                for (final installment in cycleView.previousCyclePending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: LoanInstallmentTile(
                      installment: installment,
                      onTap: () => LoanInstallmentDetailSheet.show(context, installment, loan: loan),
                    ),
                  ),
              ],
              const SizedBox(height: AppSizes.lg),
              Text('Schedule', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              if (sorted.isEmpty)
                const EmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'No payments scheduled',
                  subtitle: 'This loan has no schedule yet.',
                )
              else
                for (final installment in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: LoanInstallmentTile(
                      installment: installment,
                      onTap: () => LoanInstallmentDetailSheet.show(context, installment, loan: loan),
                    ),
                  ),

              // 10. Payment History — every real InstallmentPayment, newest
              // first, never reconstructed from Installment.amountPaid.
              if (paymentHistory.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                Text('Payment History', style: context.textTheme.titleMedium),
                const SizedBox(height: AppSizes.sm),
                for (final entry in paymentHistory)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: LoanPaymentHistoryTile(
                      entry: entry,
                      onTap: () => LoanPaymentDetailSheet.show(context, entry),
                    ),
                  ),
              ],

              // 11. Timeline — only events with real, reliable data behind
              // them (see LoanTimelineEntry.build's doc comment).
              if (timeline.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                Text('Timeline', style: context.textTheme.titleMedium),
                const SizedBox(height: AppSizes.sm),
                AppCard(
                  child: Column(
                    children: [for (final entry in timeline) LoanTimelineTile(entry: entry)],
                  ),
                ),
              ],
            ],
          );
        },
      )),
    );
  }

  Widget _buildNextPaymentCard(BuildContext context, Installment installment) {
    final status = installment.status;
    final isOverdue = status == InstallmentStatus.overdue;
    final isPartial = status == InstallmentStatus.partiallyPaid;

    final String label;
    final Color color;
    final String subtitle;
    if (isOverdue) {
      label = 'Overdue';
      color = AppColors.error;
      final daysAgo = DateTime.now().dateOnly.difference(installment.dueDate.dateOnly).inDays;
      subtitle = 'Due $daysAgo day${daysAgo == 1 ? '' : 's'} ago';
    } else if (isPartial) {
      label = 'Remaining';
      color = AppColors.warning;
      subtitle = 'Due ${installment.dueDate.fullDate}';
    } else {
      label = 'Next Payment';
      color = context.colors.primary;
      subtitle = 'Due ${installment.dueDate.fullDate}';
    }

    final amount = installment.remainingAmount;

    return AppCard(
      child: Row(
        children: [
          Icon(isOverdue ? Icons.error_outline_rounded : Icons.schedule_rounded, color: color),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                Text(subtitle, style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.instance.format(amount),
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
          Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, double value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
          Text(
            CurrencyFormatter.instance.format(value),
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasize ? context.colors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
