import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';
import 'loan.dart';
import 'loan_direction.dart';
import 'loan_financial_summary.dart';

/// One loan folded into the dashboard's aggregate totals, alongside the
/// per-loan [LoanFinancialSummary] every other screen already trusts — never
/// a second calculation of principal/outstanding/interest.
typedef LoanWithSummary = ({Loan loan, LoanFinancialSummary summary});

/// A single calendar month's scheduled repayment total — read straight off
/// installment due dates/amounts (`Installment.amountDue`), never a
/// recomputed EMI figure. [month] is always the 1st of that month.
class MonthlyRepaymentBucket {
  const MonthlyRepaymentBucket({required this.month, required this.amountDue});

  final DateTime month;
  final double amountDue;
}

/// The Loan Dashboard's whole picture — every number here is either a direct
/// sum of [LoanFinancialSummary] fields across [activeLoansProvider]'s loans,
/// or a direct read of installment due dates/statuses. Nothing here
/// re-derives interest, amortization, or payment-application logic; that
/// stays owned by [LoanFinancialSummary.from] and `InstallmentRepository`.
///
/// Deliberately loan-balance-only — see the doc comment on
/// `loanDashboardMetricsProvider` for why this is never filtered by a
/// transaction-style date range the way Cash Flow/Reports are.
class LoanDashboardMetrics {
  const LoanDashboardMetrics({
    required this.totalBorrowed,
    required this.totalLent,
    required this.borrowedOutstanding,
    required this.lentOutstanding,
    required this.totalOutstanding,
    required this.totalPaid,
    required this.totalInterestRemaining,
    required this.overdueLoanCount,
    required this.overdueAmount,
    required this.upcoming7Days,
    required this.upcoming30Days,
  });

  /// Sum of `originalPrincipal` across every active [LoanDirection.taken] loan
  /// — money the user borrowed, lifetime principal (not a cash-flow total).
  final double totalBorrowed;

  /// Sum of `originalPrincipal` across every active [LoanDirection.given] loan
  /// — money the user lent out.
  final double totalLent;

  /// Sum of `outstanding` across active [LoanDirection.taken] loans.
  final double borrowedOutstanding;

  /// Sum of `outstanding` across active [LoanDirection.given] loans.
  final double lentOutstanding;

  /// [borrowedOutstanding] + [lentOutstanding].
  final double totalOutstanding;

  /// Sum of `totalPaid` across every active loan, either direction.
  final double totalPaid;

  /// Sum of `interestRemaining` across every active loan, either direction.
  final double totalInterestRemaining;

  /// Count of active loans currently carrying at least one overdue
  /// installment (per [LoanFinancialSummary.overdueInstallments]).
  final int overdueLoanCount;

  /// Sum of `overdueAmount` across every active loan.
  final double overdueAmount;

  /// Sum of `remainingAmount` across installments due within the next 7 days
  /// (inclusive of today), across every active loan.
  final double upcoming7Days;

  /// Sum of `remainingAmount` across installments due within the next 30
  /// days (inclusive of today), across every active loan.
  final double upcoming30Days;

  static LoanDashboardMetrics from(List<LoanWithSummary> loans, {required List<Installment> Function(Loan) installmentsFor, DateTime? now}) {
    final today = (now ?? DateTime.now());
    final todayStart = DateTime(today.year, today.month, today.day);
    final in7Days = todayStart.add(const Duration(days: 7));
    final in30Days = todayStart.add(const Duration(days: 30));

    var totalBorrowed = 0.0;
    var totalLent = 0.0;
    var borrowedOutstanding = 0.0;
    var lentOutstanding = 0.0;
    var totalPaid = 0.0;
    var totalInterestRemaining = 0.0;
    var overdueLoanCount = 0;
    var overdueAmount = 0.0;
    var upcoming7Days = 0.0;
    var upcoming30Days = 0.0;

    for (final entry in loans) {
      final loan = entry.loan;
      final summary = entry.summary;

      totalPaid += summary.totalPaid;
      totalInterestRemaining += summary.interestRemaining;
      overdueAmount += summary.overdueAmount;
      if (summary.overdueInstallments > 0) overdueLoanCount++;

      if (loan.direction == LoanDirection.taken) {
        totalBorrowed += summary.originalPrincipal;
        borrowedOutstanding += summary.outstanding;
      } else {
        totalLent += summary.originalPrincipal;
        lentOutstanding += summary.outstanding;
      }

      for (final installment in installmentsFor(loan)) {
        if (installment.status == InstallmentStatus.paid || installment.status == InstallmentStatus.skipped) continue;
        final due = installment.dueDate;
        if (due.isBefore(in7Days) && !due.isBefore(todayStart)) {
          upcoming7Days += installment.remainingAmount;
        }
        if (due.isBefore(in30Days) && !due.isBefore(todayStart)) {
          upcoming30Days += installment.remainingAmount;
        }
      }
    }

    return LoanDashboardMetrics(
      totalBorrowed: totalBorrowed,
      totalLent: totalLent,
      borrowedOutstanding: borrowedOutstanding,
      lentOutstanding: lentOutstanding,
      totalOutstanding: borrowedOutstanding + lentOutstanding,
      totalPaid: totalPaid,
      totalInterestRemaining: totalInterestRemaining,
      overdueLoanCount: overdueLoanCount,
      overdueAmount: overdueAmount,
      upcoming7Days: upcoming7Days,
      upcoming30Days: upcoming30Days,
    );
  }

  /// Scheduled repayment total per calendar month across every active loan's
  /// installments — a straight sum of `Installment.amountDue`, grouped by
  /// due-month, sorted chronologically. This is the "Monthly Repayment"
  /// section's data: pure installment-schedule readout, not a new
  /// calculation. Skipped installments are excluded (nothing is actually
  /// due); paid installments are included (still part of what was
  /// *scheduled* for that month).
  static List<MonthlyRepaymentBucket> monthlyRepayments(List<Installment> installments, {int monthsAhead = 3, DateTime? now}) {
    final today = now ?? DateTime.now();
    final totals = <DateTime, double>{};
    for (final installment in installments) {
      if (installment.isSkipped) continue;
      final month = DateTime(installment.dueDate.year, installment.dueDate.month, 1);
      totals[month] = (totals[month] ?? 0) + installment.amountDue;
    }

    final months = <DateTime>[];
    for (var i = 0; i < monthsAhead; i++) {
      months.add(DateTime(today.year, today.month + i, 1));
    }

    return months.map((month) => MonthlyRepaymentBucket(month: month, amountDue: totals[month] ?? 0)).toList();
  }
}
