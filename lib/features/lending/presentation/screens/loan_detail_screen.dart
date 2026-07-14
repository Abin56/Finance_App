import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../providers/loan_providers.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/loan_installment_tile.dart';
import '../widgets/record_loan_payment_sheet.dart';

/// One loan's detail — header stats (lent/received/remaining, plus
/// principal/interest breakdown when the loan carries interest), its full
/// installment schedule, and a Record Payment entry point per installment.
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
    final installmentsAsync = ref.watch(installmentsStreamProvider(loan.scheduleId));
    final status = ref.watch(loanStatusProvider(loan));
    final remaining = ref.watch(loanRemainingAmountProvider(loan));
    final received = ref.watch(loanTotalReceivedProvider(loan));
    final repository = ref.watch(loanRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(loan.name?.isNotEmpty == true ? loan.name! : 'Loan to ${person?.name ?? 'unknown'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit loan',
            onPressed: () => LoanFormSheet.show(context, loan: loan),
          ),
          IconButton(
            icon: Icon(status.name == 'closed' ? Icons.lock_open_rounded : Icons.check_circle_outline_rounded),
            tooltip: status.name == 'closed' ? 'Reopen loan' : 'Close loan',
            onPressed: () async {
              if (loan.isClosed) {
                await repository.reopenLoan(loan);
              } else {
                await repository.closeLoan(loan);
              }
            },
          ),
        ],
      ),
      body: installmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (installments) {
          final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSizes.lg),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statRow(context, 'Loan amount', loan.loanAmount),
                    _statRow(context, 'Amount received', received),
                    _statRow(context, 'Amount left', remaining),
                    if (loan.interest != null) ...[
                      const Divider(height: AppSizes.xl),
                      _statRow(context, 'Loan amount left', _remainingPrincipal(sorted)),
                      _statRow(context, 'Interest left', _remainingInterest(sorted)),
                    ],
                  ],
                ),
              ),
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
                      onTap: installment.remainingAmount <= 0
                          ? null
                          : () => RecordLoanPaymentSheet.show(context, installment),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  /// Remaining principal across all installments, assuming each
  /// installment's own payments settle its interest portion before its
  /// principal portion (the standard repayment convention) — display-only,
  /// does not affect how `Installment.amountPaid`/`applyPayment` work.
  double _remainingPrincipal(List<Installment> installments) {
    return installments.fold(0.0, (sum, i) {
      final interestPortion = i.interestPortion ?? 0;
      final principalPortion = i.principalPortion ?? i.amountDue;
      final paidTowardPrincipal = (i.amountPaid - interestPortion).clamp(0, principalPortion);
      return sum + (principalPortion - paidTowardPrincipal);
    });
  }

  double _remainingInterest(List<Installment> installments) {
    return installments.fold(0.0, (sum, i) {
      final interestPortion = i.interestPortion ?? 0;
      final paidTowardInterest = i.amountPaid.clamp(0, interestPortion);
      return sum + (interestPortion - paidTowardInterest);
    });
  }

  Widget _statRow(BuildContext context, String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
          Text(
            CurrencyFormatter.instance.format(value),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
