import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../lending/domain/person_loan_ledger_summary.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../domain/person.dart';

/// "You owe them / They owe you / Net" — the ledger balance and loan
/// outstanding totals added together (see [PersonLoanLedgerSummary]'s own
/// doc comment for why that's always safe, never a double count), so this
/// card and [PersonLoansSummaryCard]'s "Money to receive"/"Money to pay"
/// rows always agree by construction: both read the exact same
/// `loanRemainingAmountProvider` figures, just combined differently here
/// with the person's ledger balance.
class PersonLoanLedgerSummaryCard extends ConsumerWidget {
  const PersonLoanLedgerSummaryCard({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(personLoanLedgerSummaryProvider(person.id));
    if (summary.youOweThem == 0 && summary.theyOweYou == 0) return const SizedBox.shrink();

    final netColor = summary.isNetReceivable ? AppColors.credit : AppColors.debit;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(person.name, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          if (summary.youOweThem > 0)
            _Row(label: 'You owe ${person.name}', amount: summary.youOweThem),
          if (summary.theyOweYou > 0)
            _Row(label: '${person.name} owes you', amount: summary.theyOweYou),
          const Divider(height: AppSizes.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Net', style: context.textTheme.titleSmall),
              Text(
                '${CurrencyFormatter.instance.format(summary.net.abs())} ${summary.isNetReceivable ? 'receivable' : 'payable'}',
                style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: netColor),
              ),
            ],
          ),
          if (summary.loanGivenTotal > 0 || summary.loanTakenTotal > 0) ...[
            const Divider(height: AppSizes.lg),
            Text('Loans', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.sm),
            if (summary.loanGivenTotal > 0)
              _LoanDirectionRow(label: 'Given', total: summary.loanGivenTotal, outstanding: summary.loanGivenOutstanding),
            if (summary.loanTakenTotal > 0)
              _LoanDirectionRow(label: 'Borrowed', total: summary.loanTakenTotal, outstanding: summary.loanTakenOutstanding),
          ],
        ],
      ),
    );
  }
}

class _LoanDirectionRow extends StatelessWidget {
  const _LoanDirectionRow({required this.label, required this.total, required this.outstanding});

  final String label;
  final double total;
  final double outstanding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(CurrencyFormatter.instance.format(total), style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Outstanding', style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
              Text(
                CurrencyFormatter.instance.format(outstanding),
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.amount});

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
