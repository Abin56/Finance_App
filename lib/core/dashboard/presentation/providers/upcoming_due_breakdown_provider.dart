import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/people/presentation/providers/people_providers.dart';
import '../../../../features/people/presentation/providers/person_statement_grouping_providers.dart';
import '../../../payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'upcoming_due_provider.dart';

/// What the Upcoming Due bottom sheet shows for one row — a strict "which
/// existing fields make up this total" view, never a new financial figure.
/// Every field here is either read straight off an existing domain object
/// (e.g. [Statement.totalAmount], [Installment.principalPortion]) or is a
/// filter+sum over an existing per-item provider (documented per case in
/// [upcomingDueBreakdownProvider]) — no status/remaining-amount/interest
/// math is computed here that isn't already computed elsewhere.
sealed class UpcomingDueBreakdown {
  const UpcomingDueBreakdown();
}

/// Credit Card statement: total vs. the portion other people owe back
/// (split-expense shares tracked against this statement's transactions),
/// via [personStatementGroupsProvider] summed across every person and
/// filtered to this one statement — the same per-person `share` field the
/// People screen already reads, just re-grouped by statement instead of by
/// person. [transactionCount] is the same `statement.contains(t.dateTime)`
/// filter `StatementDetailScreen` already applies.
class CreditCardBreakdown extends UpcomingDueBreakdown {
  const CreditCardBreakdown({
    required this.totalAmount,
    required this.othersShare,
    required this.transactionCount,
  });

  final double totalAmount;
  final double othersShare;
  final int transactionCount;
  double get myShare => totalAmount - othersShare;
}

/// A Bill is always entirely the user's own expense — no split concept
/// exists on [Bill]/[BillOccurrence] at all, so this isn't a 0-value guess,
/// it's the correct answer for every bill by construction.
class BillBreakdown extends UpcomingDueBreakdown {
  const BillBreakdown({required this.amount});

  final double amount;
}

/// Split Expense: [Expense.myShare]/[Expense.othersShare] read directly —
/// no provider needed, these are plain getters on the already-loaded
/// [Expense].
class SplitExpenseBreakdown extends UpcomingDueBreakdown {
  const SplitExpenseBreakdown({required this.myShare, required this.othersShare});

  final double myShare;
  final double othersShare;
  double get total => myShare + othersShare;
}

/// EMI installment: [Installment.principalPortion]/[interestPortion] when
/// the schedule carries interest, else both null — a 0%-interest EMI
/// genuinely has no split to show, not a hidden zero.
class EmiBreakdown extends UpcomingDueBreakdown {
  const EmiBreakdown({required this.amountDue, required this.principalPortion, required this.interestPortion});

  final double amountDue;
  final double? principalPortion;
  final double? interestPortion;
  bool get hasInterestSplit => principalPortion != null && interestPortion != null;
}

/// Loan installment: outstanding principal/interest summed from
/// [Installment.principalPortion]/[interestPortion] across every
/// not-yet-fully-paid installment on the loan's schedule — the same
/// per-installment fields [EmiBreakdown] reads, just summed across the
/// remaining schedule instead of read off one installment, since "what's
/// left to repay" is naturally a whole-loan figure. Null split fields
/// (non-interest loan) are treated as 0 interest / full remaining-as-
/// principal for the sum, since that matches [Installment.remainingAmount]
/// exactly when a loan carries no interest.
class LoanBreakdown extends UpcomingDueBreakdown {
  const LoanBreakdown({
    required this.totalOutstanding,
    required this.outstandingPrincipal,
    required this.outstandingInterest,
  });

  final double totalOutstanding;
  final double outstandingPrincipal;
  final double outstandingInterest;
}

/// Resolves one [UpcomingDueItem] (looked up by [UpcomingDueItem.routeId]
/// + [UpcomingDueItem.dueDate], the same join key already unique per row)
/// into its [UpcomingDueBreakdown]. Returns null only if the underlying
/// record can no longer be found (e.g. deleted between the row rendering
/// and the sheet opening).
final upcomingDueBreakdownProvider = Provider.family<UpcomingDueBreakdown?, UpcomingDueItem>((ref, item) {
  switch (item.kind) {
    case UpcomingDueKind.creditCard:
      final cards = ref.watch(activeCreditCardsProvider);
      final card = cards.where((c) => c.id == item.routeId).firstOrNull;
      if (card == null) return null;
      final statements = ref.watch(statementsWithLiveTotalsProvider(card.id));
      final statement = statements.where((s) => s.id == item.secondaryRouteId).firstOrNull;
      if (statement == null) return null;

      final people = ref.watch(peopleStreamProvider).value ?? const [];
      var othersShare = 0.0;
      for (final person in people) {
        final groups = ref.watch(personStatementGroupsProvider(person.id));
        final group = groups.where((g) => g.statement.id == statement.id).firstOrNull;
        if (group == null) continue;
        othersShare += group.items.fold(0.0, (sum, i) => sum + i.share);
      }

      final cardTransactions = ref.watch(transactionsForCardProvider(card.id));
      final transactionCount = cardTransactions.where((t) => statement.contains(t.dateTime)).length;

      return CreditCardBreakdown(
        totalAmount: statement.totalAmount,
        othersShare: othersShare,
        transactionCount: transactionCount,
      );

    case UpcomingDueKind.bill:
      final bills = ref.watch(billsStreamProvider).value ?? const [];
      final bill = bills.where((b) => b.id == item.routeId).firstOrNull;
      if (bill == null) return null;
      return BillBreakdown(amount: item.remaining);

    case UpcomingDueKind.splitExpense:
      final expense = ref.watch(expenseForTransactionProvider(item.routeId));
      if (expense == null) return null;
      return SplitExpenseBreakdown(myShare: expense.myShare, othersShare: expense.othersShare);

    case UpcomingDueKind.emi:
      final emis = ref.watch(activeEmisProvider);
      final emi = emis.where((e) => e.id == item.routeId).firstOrNull;
      if (emi == null) return null;
      final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
      final installment = installments.where((i) => i.dueDate == item.dueDate).firstOrNull;
      if (installment == null) return null;
      return EmiBreakdown(
        amountDue: installment.amountDue,
        principalPortion: installment.principalPortion,
        interestPortion: installment.interestPortion,
      );

    case UpcomingDueKind.loan:
      final loans = ref.watch(activeLoansProvider);
      final loan = loans.where((l) => l.id == item.routeId).firstOrNull;
      if (loan == null) return null;
      final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
      var principal = 0.0;
      var interest = 0.0;
      for (final installment in installments) {
        if (installment.remainingAmount <= 0 || installment.isSkipped) continue;
        final p = installment.principalPortion;
        final i = installment.interestPortion;
        if (p != null && i != null) {
          final paidFraction = installment.amountDue == 0 ? 0.0 : installment.amountPaid / installment.amountDue;
          principal += p * (1 - paidFraction);
          interest += i * (1 - paidFraction);
        } else {
          principal += installment.remainingAmount;
        }
      }
      return LoanBreakdown(
        totalOutstanding: principal + interest,
        outstandingPrincipal: principal,
        outstandingInterest: interest,
      );
  }
});
