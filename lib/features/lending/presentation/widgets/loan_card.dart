import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../people/domain/person.dart';
import '../../domain/loan.dart';
import '../../domain/loan_category.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_status.dart';
import '../providers/loan_providers.dart';
import 'loan_emi_ui.dart';

/// Who the loan is with — the Person for a personal loan, the institution
/// otherwise. Same fallback the web card uses (`lenderName`).
String loanCounterpartyName(Loan loan, Person? person) {
  if (loan.category == LoanCategory.personal) return person?.name ?? 'Unknown';
  final name = loan.institutionName?.trim();
  return name == null || name.isEmpty ? 'Bank / lender' : name;
}

/// The loan's own name, else who it's with — so a card never just says "Loan".
String loanCardTitle(Loan loan, Person? person) {
  final name = loan.name?.trim();
  return name != null && name.isNotEmpty
      ? name
      : loanCounterpartyName(loan, person);
}

String loanInterestShort(Loan loan) {
  final interest = loan.interest;
  if (interest == null) return 'No interest';
  final unit = interest.period == InterestPeriod.yearly ? 'p.a.' : 'p.m.';
  return '${interest.ratePercent}% $unit';
}

/// Non-routine states only; an active borrowed loan carries no badge.
List<LoanEmiBadge> loanBadges(
  BuildContext context,
  Loan loan,
  LoanStatus status,
) {
  return [
    if (loan.direction == LoanDirection.given)
      const LoanEmiBadge('Money I lent', AppColors.success),
    if (status == LoanStatus.overdue)
      const LoanEmiBadge('Missed payment', AppColors.error),
    if (status == LoanStatus.closed)
      LoanEmiBadge('Closed', loanEmiNeutralBadgeColor(context)),
  ];
}

/// Loan list card for the Loan & EMI screen — the twin of web's `LoanCard`.
/// Figures come from [loanFinancialSummaryProvider]; nothing is recomputed.
class LoanCard extends ConsumerWidget {
  const LoanCard({
    super.key,
    required this.loan,
    required this.person,
    required this.onTap,
    this.payer,
  });

  final Loan loan;
  final Person? person;
  final Person? payer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loanStatusProvider(loan));
    final summary = ref.watch(loanFinancialSummaryProvider(loan));
    final installments =
        ref.watch(installmentsStreamProvider(loan.scheduleId)).value ??
        const [];
    final isClosed = status == LoanStatus.closed;
    final hasOwnName = loan.name?.trim().isNotEmpty == true;
    final next = isClosed ? null : summary.nextInstallment;

    return LoanEmiCard(
      icon: LoanEmiCopy.loanIcon,
      name: loanCardTitle(loan, person),
      source: [
        hasOwnName
            ? loanCounterpartyName(loan, person)
            : (loan.category == LoanCategory.personal
                  ? 'Personal loan'
                  : 'Bank loan'),
        if (loan.interest != null) loanInterestShort(loan),
      ].join(' · '),
      badges: loanBadges(context, loan, status),
      outstandingLabel: loan.direction == LoanDirection.given
          ? LoanEmiCopy.stillToReceive
          : LoanEmiCopy.outstanding,
      outstanding: summary.outstanding,
      nextAmount: next?.remainingAmount,
      nextDate: next?.dueDate,
      overdue:
          status == LoanStatus.overdue ||
          (next != null && loanEmiDaysUntil(next.dueDate) < 0),
      paid: summary.paidInstallments,
      total: installments.length,
      links: [
        if (payer != null)
          (Icons.volunteer_activism_outlined, 'Paid by ${payer!.name}'),
      ],
      muted: isClosed,
      onTap: onTap,
    );
  }
}
