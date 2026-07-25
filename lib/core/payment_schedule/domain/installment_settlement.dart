import '../../errors/app_exception.dart';
import 'installment.dart';

/// One [Installment] and the portion of a lump-sum settlement amount
/// applied to it — the fan-out result of [InstallmentSettlement.plan].
typedef InstallmentSettlementPortion = ({Installment installment, double portion});

/// Result of [InstallmentSettlement.plan] — the ordered portions to apply,
/// plus whatever part of the requested amount couldn't be allocated because
/// it exceeded every installment's total remaining balance.
class InstallmentSettlementPlan {
  const InstallmentSettlementPlan({required this.portions, required this.unallocated});

  final List<InstallmentSettlementPortion> portions;
  final double unallocated;

  double get totalApplied => portions.fold(0.0, (sum, p) => sum + p.portion);
}

/// Pure, feature-agnostic "pay a lump sum across several installments,
/// oldest-first" planner — the [Installment]-only counterpart to
/// `ExpenseRepository.settleAcrossPending`'s fan-out loop, structurally
/// separate from it (no import of, no call into `expense_repository.dart`)
/// since that method is typed to `Expense`/`ExpenseParticipant` and is
/// People/Expense's own frozen settlement primitive. EMI and Loan both call
/// this same function instead of each hand-rolling their own fan-out.
abstract class InstallmentSettlement {
  InstallmentSettlement._();

  /// Applies [amount] across [installments] (already sorted oldest-due-first
  /// by the caller — mirrors `settleAcrossPending`'s own "caller pre-sorts"
  /// contract; this does not re-sort) until [amount] is exhausted or every
  /// installment is covered. Installments with `remainingAmount <= 0` are
  /// skipped entirely (never appear in the result). The last installment
  /// touched may receive a partial portion less than its own
  /// `remainingAmount` if [amount] runs out first. Never returns a portion
  /// exceeding an installment's own `remainingAmount`, and never allocates
  /// more than `amount`. Any excess beyond total outstanding is reported via
  /// [InstallmentSettlementPlan.unallocated] rather than posted anywhere —
  /// unlike `settleAcrossPending`, EMI/Loan have no ledger-remainder concept
  /// to fall back to.
  static InstallmentSettlementPlan plan(List<Installment> installments, double amount) {
    if (amount <= 0) {
      throw const AppException('Settlement amount must be greater than 0');
    }
    var remaining = amount;
    final portions = <InstallmentSettlementPortion>[];
    for (final installment in installments) {
      if (remaining <= 0) break;
      final owed = installment.remainingAmount;
      if (owed <= 0) continue;
      final portion = owed < remaining ? owed : remaining;
      portions.add((installment: installment, portion: portion));
      remaining -= portion;
    }
    return InstallmentSettlementPlan(portions: portions, unallocated: remaining);
  }
}
