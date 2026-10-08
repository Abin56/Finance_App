import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/loan.dart';
import '../../domain/loan_category.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_financial_summary.dart';
import '../../domain/loan_repayment_type.dart';
import '../../domain/loan_status.dart';
import '../providers/loan_providers.dart';
import '../widgets/loan_card.dart';
import '../widgets/loan_emi_ui.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/loan_installment_detail_sheet.dart';
import '../widgets/loan_installment_tile.dart';
import '../widgets/loan_interest_breakdown_card.dart';
import '../widgets/loan_financial_history_tile.dart';
import '../widgets/loan_timeline_tile.dart';
import '../widgets/record_loan_lump_sum_settlement_sheet.dart';
import '../widgets/record_loan_payment_sheet.dart';
import '../widgets/loan_adjustment_sheet.dart';

String _money(double amount) => CurrencyFormatter.instance.format(amount);

/// One loan's details — the outstanding balance first (hero), then one
/// primary action (Record payment) with the rarer money actions under
/// "More", the key facts, what the loan is linked to, and the full
/// installment schedule and history. All numbers come from
/// `LoanFinancialSummary` (via `loanFinancialSummaryProvider`) or direct
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
    final installmentsAsync = ref.watch(
      installmentsStreamProvider(loan.scheduleId),
    );
    final status = ref.watch(loanStatusProvider(loan));
    final summary = ref.watch(loanFinancialSummaryProvider(loan));
    final repository = ref.watch(loanRepositoryProvider);
    final cycleView = ref.watch(loanCycleViewRecordProvider(loan));
    final financialHistory = ref.watch(loanFinancialHistoryProvider(loan));
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final timeline = ref.watch(loanTimelineProvider(loan));

    final isGiven = loan.direction == LoanDirection.given;
    final isInstitutional = loan.category == LoanCategory.institutional;
    final isInstallment = loan.repaymentType == LoanRepaymentType.installment;
    final isClosed = status == LoanStatus.closed;

    Future<void> toggleClosed() async {
      if (loan.isClosed) {
        await repository.reopenLoan(
          loan,
          currentInstallments: installmentsAsync.value ?? const [],
        );
      } else {
        await repository.closeLoan(loan);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loanCardTitle(loan, person)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit loan',
            onPressed: () => LoanFormSheet.show(context, loan: loan),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (_) => toggleClosed(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isClosed
                        ? Icons.lock_open_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
                  title: Text(isClosed ? 'Reopen loan' : 'Close loan'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: installmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong: $error')),
        data: (installments) {
          final sorted = [...installments]
            ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
          final next = isClosed ? null : summary.nextInstallment;
          final installmentAmount =
              (summary.nextInstallment ?? sorted.lastOrNull)?.amountDue ?? 0.0;
          final canPay =
              !isClosed &&
              summary.outstanding > 0 &&
              summary.nextInstallment != null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              AppSizes.sm,
              AppSizes.lg,
              AppSizes.xxl,
            ),
            children: [
              // 1. What's left, and what's next.
              LoanEmiDetailHero(
                kindLabel: LoanEmiCopy.loan,
                label: isGiven
                    ? LoanEmiCopy.stillToReceive
                    : LoanEmiCopy.outstanding,
                amount: summary.outstanding,
                paid: summary.paidInstallments,
                total: isInstallment ? sorted.length : 0,
                badges: loanBadges(context, loan, status),
                nextAmount: next?.remainingAmount,
                nextDate: next?.dueDate,
                nextSequence: isInstallment ? next?.sequenceNumber : null,
              ),
              const SizedBox(height: AppSizes.md),

              // 2. One primary action; the rest one tap away.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: canPay
                          ? () => RecordLoanPaymentSheet.show(
                              context,
                              summary.nextInstallment!,
                              loan: loan,
                            )
                          : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(
                        isGiven ? 'Record received' : 'Record payment',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed:
                        isClosed || (!isInstallment && summary.outstanding <= 0)
                        ? null
                        : () => _showMoreActions(
                            context,
                            loan,
                            summary,
                            sorted,
                            isInstallment,
                          ),
                    icon: const Icon(Icons.more_horiz_rounded),
                    label: const Text('More'),
                  ),
                ],
              ),
              if (isClosed)
                Padding(
                  padding: const EdgeInsets.only(top: AppSizes.sm),
                  child: Text(
                    'This loan is closed. Reopen it from the ⋮ menu to record payments.',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: loanEmiSecondaryText(context),
                    ),
                  ),
                ),

              // 3. Overdue callout.
              if (summary.overdueInstallments > 0) ...[
                const SizedBox(height: AppSizes.md),
                AppCard(
                  color: AppColors.error.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          '${summary.overdueInstallments} missed payment${summary.overdueInstallments == 1 ? '' : 's'}',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _money(summary.overdueAmount),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 4. Key facts.
              const SizedBox(height: AppSizes.lg),
              const LoanEmiSectionTitle('Details'),
              LoanEmiFactGrid(
                facts: [
                  LoanEmiFact('Original amount', _money(loan.loanAmount)),
                  if (isInstallment)
                    LoanEmiFact(
                      'Installment',
                      _money(installmentAmount),
                      strong: true,
                    ),
                  LoanEmiFact(
                    isGiven ? 'Received so far' : 'Paid so far',
                    _money(summary.totalPaid),
                  ),
                  LoanEmiFact(
                    'Total payable',
                    _money(summary.totalScheduledPayable),
                  ),
                  if (loan.interest != null) ...[
                    LoanEmiFact(
                      'Principal left',
                      _money(summary.principalRemaining),
                    ),
                    LoanEmiFact(
                      'Interest left',
                      _money(summary.interestRemaining),
                    ),
                  ],
                  LoanEmiFact(
                    'Interest',
                    loan.interest == null
                        ? 'No interest'
                        : '${loanInterestShort(loan)} · ${loan.interest!.type == InterestType.flat ? 'flat' : 'reducing'}',
                  ),
                  LoanEmiFact(
                    'Repayment',
                    isInstallment
                        ? '${loan.installmentCount ?? sorted.length} × ${loan.installmentFrequency == ScheduleType.weekly ? 'weekly' : 'monthly'}'
                        : 'One-time${loan.dueDate != null ? ' · ${loan.dueDate!.shortDate}' : ''}',
                  ),
                  LoanEmiFact('Loan date', loan.loanDate.fullDate),
                ],
              ),

              // 5. What it's linked to.
              const SizedBox(height: AppSizes.lg),
              const LoanEmiSectionTitle('Linked'),
              LoanEmiGroup(
                children: [
                  LoanEmiLinkedRow(
                    icon: isInstitutional
                        ? Icons.account_balance_outlined
                        : Icons.person_outline_rounded,
                    label: isGiven ? 'Loan given to' : 'Loan taken from',
                    value: loanCounterpartyName(loan, person),
                    onOpen: person == null
                        ? null
                        : () =>
                              context.push('${AppRoutes.people}/${person.id}'),
                  ),
                  Divider(height: 1, color: context.colors.outline),
                  LoanEmiLinkedRow(
                    icon: Icons.volunteer_activism_outlined,
                    label: 'Installments paid by',
                    value: payer?.name ?? 'You',
                    onOpen: payer == null
                        ? null
                        : () => context.push('${AppRoutes.people}/${payer.id}'),
                  ),
                ],
              ),

              if (isInstitutional && _hasBankDetails(loan)) ...[
                const SizedBox(height: AppSizes.lg),
                const LoanEmiSectionTitle('Bank details'),
                LoanEmiFactGrid(
                  facts: [
                    if (loan.loanType?.isNotEmpty == true)
                      LoanEmiFact('Type of loan', loan.loanType!),
                    if (loan.loanNumber?.isNotEmpty == true)
                      LoanEmiFact('Loan number', loan.loanNumber!),
                    if (loan.accountNumber?.isNotEmpty == true)
                      LoanEmiFact('Account number', loan.accountNumber!),
                    if (loan.branch?.isNotEmpty == true)
                      LoanEmiFact('Branch', loan.branch!),
                  ],
                ),
              ],

              // 6. Interest breakdown / amortization — only for interest-
              // bearing installment loans.
              if (loan.interest != null &&
                  isInstallment &&
                  sorted.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                LoanInterestBreakdownCard(
                  loan: loan,
                  installments: sorted,
                  summary: summary,
                ),
              ],

              // 7. Installments — previous cycle pending, then the schedule.
              if (cycleView.previousCyclePending.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                const LoanEmiSectionTitle('Previous cycle pending'),
                for (final installment in cycleView.previousCyclePending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: LoanInstallmentTile(
                      installment: installment,
                      onTap: () => LoanInstallmentDetailSheet.show(
                        context,
                        installment,
                        loan: loan,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: AppSizes.lg),
              LoanEmiSectionTitle(
                'Installments',
                trailing: Text(
                  '${summary.paidInstallments} of ${sorted.length} paid',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: loanEmiSecondaryText(context),
                  ),
                ),
              ),
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
                      onTap: () => LoanInstallmentDetailSheet.show(
                        context,
                        installment,
                        loan: loan,
                      ),
                    ),
                  ),

              // 8. Payment history — every real InstallmentPayment, newest
              // first, never reconstructed from Installment.amountPaid.
              if (financialHistory.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                const LoanEmiSectionTitle('Payment history'),
                for (final action in financialHistory)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: LoanFinancialHistoryTile(
                      action: action,
                      accountLabel: accounts
                          .where((account) => account.id == action.accountId)
                          .firstOrNull
                          ?.name,
                    ),
                  ),
              ],

              // 9. Timeline — only events with real, reliable data behind
              // them (see LoanTimelineEntry.build's doc comment).
              if (timeline.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                const LoanEmiSectionTitle('Timeline'),
                AppCard(
                  child: Column(
                    children: [
                      for (final entry in timeline)
                        LoanTimelineTile(entry: entry),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  bool _hasBankDetails(Loan loan) =>
      loan.loanType?.isNotEmpty == true ||
      loan.loanNumber?.isNotEmpty == true ||
      loan.accountNumber?.isNotEmpty == true ||
      loan.branch?.isNotEmpty == true;

  /// The rarer money actions — same set and wording as web's "More payment
  /// options", each opening its existing sheet unchanged.
  Future<void> _showMoreActions(
    BuildContext context,
    Loan loan,
    LoanFinancialSummary summary,
    List<Installment> sorted,
    bool isInstallment,
  ) {
    final isGiven = loan.direction == LoanDirection.given;
    final hasBalance = summary.outstanding > 0;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return ListTile(
            minTileHeight: 64,
            leading: LoanEmiIconBox(icon: icon, size: 38),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasBalance)
                option(
                  icon: Icons.request_quote_outlined,
                  title: 'Pay Multiple EMIs',
                  subtitle:
                      'Make one payment toward multiple unpaid installments.',
                  onTap: () =>
                      RecordLoanLumpSumSettlementSheet.show(context, loan),
                ),
              if (isInstallment && hasBalance)
                option(
                  icon: Icons.trending_down_rounded,
                  title: 'Pay Extra Principal',
                  subtitle:
                      'Pay extra to reduce your remaining loan principal.',
                  onTap: () => LoanAdjustmentSheet.show(
                    context,
                    loan: loan,
                    installments: sorted,
                    kind: LoanAdjustmentKind.principalPrepayment,
                  ),
                ),
              if (isInstallment)
                option(
                  icon: Icons.add_card_rounded,
                  title: isGiven ? 'Give More Money' : 'Borrow More Money',
                  subtitle: isGiven
                      ? 'Add more money given under this loan.'
                      : 'Add more money received under this loan.',
                  onTap: () => LoanAdjustmentSheet.show(
                    context,
                    loan: loan,
                    installments: sorted,
                    kind: LoanAdjustmentKind.additionalDisbursement,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
