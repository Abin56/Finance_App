import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/interest/interest_calculator.dart';
import '../../../core/interest/interest_period.dart';
import '../../../core/payment_schedule/data/installment_repository.dart';
import '../../../core/payment_schedule/data/payment_schedule_repository.dart';
import '../../../core/payment_schedule/domain/owner_type.dart';
import '../../../core/payment_schedule/domain/precomputed_installment_amount.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/loan.dart';
import '../domain/loan_interest.dart';
import '../domain/loan_repayment_type.dart';

/// Loan-specific persistence on top of the generic CRUD/soft-delete
/// repository. Bridges the feature-agnostic `PaymentScheduleRepository`/
/// `InstallmentRepository` (payment tracking) and `InterestCalculator`
/// (interest math) — neither of those core engines knows what a "loan" is;
/// this repository is where the two are composed.
class LoanRepository extends FirestoreCrudRepository<Loan> {
  LoanRepository(super.collection, this.paymentScheduleRepository, this._installmentRepositoryFor);

  final PaymentScheduleRepository paymentScheduleRepository;

  /// Resolves an `InstallmentRepository` scoped to a given schedule id —
  /// installment collections are schedule-scoped, so this is supplied by
  /// the provider layer (which owns Riverpod's per-schedule repository
  /// instances) rather than constructed directly here.
  final InstallmentRepository Function(String scheduleId) _installmentRepositoryFor;

  Future<Loan> createLoan({
    required String personId,
    required double loanAmount,
    required DateTime loanDate,
    required LoanRepaymentType repaymentType,
    String? name,
    LoanInterest? interest,
    DateTime? dueDate,
    ScheduleType? installmentFrequency,
    int? installmentCount,
    String notes = '',
  }) async {
    if (loanAmount <= 0) {
      throw const AppException('Loan amount must be greater than 0');
    }
    if (repaymentType == LoanRepaymentType.oneTime && dueDate == null) {
      throw const AppException('One-time loans need a due date');
    }
    if (repaymentType == LoanRepaymentType.installment) {
      if (installmentFrequency == null) {
        throw const AppException('Monthly payment loans need a repayment frequency');
      }
      if (installmentCount == null || installmentCount < 1) {
        throw const AppException('Monthly payment loans need at least 1 payment');
      }
    }
    if (interest != null && interest.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }

    final effectiveInstallmentCount = repaymentType == LoanRepaymentType.oneTime ? 1 : installmentCount!;
    final effectiveScheduleType =
        repaymentType == LoanRepaymentType.oneTime ? ScheduleType.oneTime : installmentFrequency!;

    List<PrecomputedInstallmentAmount>? precomputed;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: loanAmount,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: effectiveInstallmentCount,
        installmentFrequency: _interestPeriodFor(effectiveScheduleType),
      );
      precomputed = breakdown.periods
          .map((p) => PrecomputedInstallmentAmount(
                amountDue: p.paymentAmount,
                principalPortion: p.principalPortion,
                interestPortion: p.interestPortion,
              ))
          .toList();
    }

    final loanId = IdGenerator.generate();
    final totalAmount = precomputed == null ? loanAmount : precomputed.fold(0.0, (sum, p) => sum + p.amountDue);

    final schedule = await paymentScheduleRepository.createSchedule(
      ownerType: OwnerType.loan,
      ownerId: loanId,
      totalAmount: totalAmount,
      scheduleType: effectiveScheduleType,
      firstDueDate: repaymentType == LoanRepaymentType.oneTime ? dueDate! : loanDate,
      installmentCount: effectiveInstallmentCount,
    );

    await _installmentRepositoryFor(schedule.id).generateInstallments(schedule, precomputedAmounts: precomputed);

    final loan = Loan(
      id: loanId,
      personId: personId,
      name: name,
      loanAmount: loanAmount,
      interest: interest,
      loanDate: loanDate,
      repaymentType: repaymentType,
      dueDate: repaymentType == LoanRepaymentType.oneTime ? dueDate : null,
      installmentFrequency: repaymentType == LoanRepaymentType.installment ? installmentFrequency : null,
      installmentCount: repaymentType == LoanRepaymentType.installment ? installmentCount : null,
      notes: notes,
      scheduleId: schedule.id,
      createdAt: DateTime.now(),
    );
    await add(loan.id, loan);
    return loan;
  }

  /// [name]/[notes]/[dueDate] (one-time loans only) are editable
  /// post-creation. [loanAmount] locks once [hasPayments] is true (mirrors
  /// `Person.openingBalance`/`Account.openingBalance`'s immutable-after-use
  /// posture). [repaymentType]/[interest]/[installmentFrequency]/
  /// [installmentCount] are never editable — they drive the one-shot
  /// schedule/installment generation in [createLoan], with no "regenerate"
  /// path, so this method doesn't accept them at all.
  Future<void> editLoan(
    Loan loan, {
    required bool hasPayments,
    String? name,
    double? loanAmount,
    DateTime? dueDate,
    String? notes,
  }) async {
    if (loanAmount != null) {
      if (loanAmount <= 0) {
        throw const AppException('Loan amount must be greater than 0');
      }
      if (hasPayments) {
        throw const AppException('Loan amount cannot be changed after a payment has been recorded');
      }
    }
    if (dueDate != null && loan.repaymentType != LoanRepaymentType.oneTime) {
      throw const AppException('Only one-time loans have an editable due date');
    }

    loan.updateField(field: 'name', oldValue: loan.name, newValue: name, apply: (v) => loan.name = v);
    loan.updateField(
      field: 'loanAmount',
      oldValue: loan.loanAmount,
      newValue: loanAmount,
      apply: (v) => loan.loanAmount = v,
    );
    loan.updateField(field: 'notes', oldValue: loan.notes, newValue: notes, apply: (v) => loan.notes = v);
    await update(loan);
  }

  Future<void> closeLoan(Loan loan) async {
    if (loan.isClosed) return;
    loan.recordEdit(field: 'isClosed', oldValue: 'false', newValue: 'true');
    loan.isClosed = true;
    await update(loan);
  }

  Future<void> reopenLoan(Loan loan) async {
    if (!loan.isClosed) return;
    loan.recordEdit(field: 'isClosed', oldValue: 'true', newValue: 'false');
    loan.isClosed = false;
    await update(loan);
  }

  /// Maps an installment cadence to the nearest `InterestPeriod` for rate
  /// normalization. `InterestCalculator` only knows monthly/yearly;
  /// `ScheduleType` has no yearly cadence, so oneTime/weekly/monthly/custom
  /// all normalize to monthly, the closest equivalent for each.
  InterestPeriod _interestPeriodFor(ScheduleType scheduleType) => InterestPeriod.monthly;
}
