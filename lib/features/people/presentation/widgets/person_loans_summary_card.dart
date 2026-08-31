import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../lending/domain/loan.dart';
import '../../../lending/domain/loan_category.dart';
import '../../../lending/domain/loan_direction.dart';
import '../../../lending/domain/loan_status.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../lending/presentation/widgets/loan_tile.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';

/// This person's Loans, folded into "Money to receive"/"Money to pay"
/// totals, active/completed lists, and an "Upcoming EMI" reminder — the
/// Loans module's own view of a person, distinct from
/// [PersonPendingBreakdown]'s generic ledger-category netting (which nets
/// given/taken loan activity together under one "Lending" line and doesn't
/// separate active from completed loans).
///
/// Sources loans two ways: [loansForPersonProvider] (this person is the
/// lender/counterparty via [Loan.personId]) and [loansPayableByPersonProvider]
/// (this person actually pays a loan on the account owner's behalf via
/// [Loan.payerPersonId] — e.g. a bank loan a friend pays the EMIs for),
/// merged and de-duplicated by loan id.
class PersonLoansSummaryCard extends ConsumerWidget {
  const PersonLoansSummaryCard({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asLender = ref.watch(loansForPersonProvider(person.id));
    final asPayer = ref.watch(loansPayableByPersonProvider(person.id));
    final loans = <String, Loan>{
      for (final loan in asLender) loan.id: loan,
      for (final loan in asPayer) loan.id: loan,
    }.values.toList();
    if (loans.isEmpty) return const SizedBox.shrink();

    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final personById = {for (final p in people) p.id: p};

    final active = <Loan>[];
    final completed = <Loan>[];
    var toReceive = 0.0;
    var toPay = 0.0;

    for (final loan in loans) {
      final status = ref.watch(loanStatusProvider(loan));
      if (status == LoanStatus.closed) {
        completed.add(loan);
        continue;
      }
      active.add(loan);
      final remaining = ref.watch(loanRemainingAmountProvider(loan));
      if (loan.direction == LoanDirection.given) {
        toReceive += remaining;
      } else {
        toPay += remaining;
      }
    }

    final upcoming = <({Loan loan, Installment installment})>[
      for (final loan in active)
        if (ref.watch(loanNextUpcomingInstallmentProvider(loan)) case final next?) (loan: loan, installment: next),
    ]..sort((a, b) => a.installment.dueDate.compareTo(b.installment.dueDate));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Loans', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          if (toReceive > 0) _TotalRow(label: 'Money to receive', amount: toReceive),
          if (toPay > 0) _TotalRow(label: 'Money to pay', amount: toPay),
          if (upcoming.isNotEmpty) ...[
            const Divider(height: AppSizes.lg),
            Text('Upcoming EMI', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.sm),
            for (final item in upcoming.take(5))
              _UpcomingEmiRow(
                loan: item.loan,
                installment: item.installment,
                counterpartyName: item.loan.personId == person.id
                    ? null
                    : (personById[item.loan.personId]?.name),
                isPayerOnly: item.loan.personId != person.id,
              ),
          ],
          if (active.isNotEmpty) ...[
            const Divider(height: AppSizes.lg),
            Text('Active', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.sm),
            for (final loan in active)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: LoanTile(
                  loan: loan,
                  person: loan.personId == person.id ? person : personById[loan.personId],
                  onTap: () => context.push('${AppRoutes.loans}/${loan.id}'),
                ),
              ),
          ],
          if (completed.isNotEmpty) ...[
            const Divider(height: AppSizes.lg),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Completed (${completed.length})', style: context.textTheme.titleSmall),
              children: [
                for (final loan in completed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: LoanTile(
                      loan: loan,
                      person: loan.personId == person.id ? person : personById[loan.personId],
                      onTap: () => context.push('${AppRoutes.loans}/${loan.id}'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingEmiRow extends StatelessWidget {
  const _UpcomingEmiRow({
    required this.loan,
    required this.installment,
    required this.counterpartyName,
    required this.isPayerOnly,
  });

  final Loan loan;
  final Installment installment;
  final String? counterpartyName;
  final bool isPayerOnly;

  /// Mirrors [loanDisplayTitle]'s fallback logic, but that helper needs a
  /// full `Person` for its personal-loan branch — this row only ever has
  /// the counterparty's resolved display name on hand, not their whole
  /// record, so the fallback is reproduced directly here instead.
  String get _title {
    if (loan.name?.isNotEmpty == true) return loan.name!;
    if (loan.category == LoanCategory.personal) return 'Loan to ${counterpartyName ?? 'unknown'}';
    return loan.institutionName ?? 'Institutional Loan';
  }

  @override
  Widget build(BuildContext context) {
    final title = _title;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Text(
                      'Due ${installment.dueDate.day}/${installment.dueDate.month}/${installment.dueDate.year}',
                      style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                    ),
                    if (isPayerOnly) ...[
                      const SizedBox(width: AppSizes.xs),
                      Text(
                        '· Pays this for you',
                        style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.instance.format(installment.remainingAmount),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
          Text(
            CurrencyFormatter.instance.format(amount),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
