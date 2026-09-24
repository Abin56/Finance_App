import '../../../core/constants/firestore_constants.dart';
import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/interest/interest_calculator.dart';
import '../../../core/interest/interest_period.dart';
import '../../../core/payment_schedule/data/installment_repository.dart';
import '../../../core/payment_schedule/data/payment_schedule_repository.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/owner_type.dart';
import '../../../core/payment_schedule/domain/payment_schedule.dart';
import '../../../core/payment_schedule/domain/precomputed_installment_amount.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../core/services/reminder_notification_service.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/reminder_offset_label.dart';
import '../domain/loan.dart';
import '../domain/loan_category.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_interest.dart';
import '../domain/loan_repayment_type.dart';

/// Fixed reminder offsets for Loans, mirroring EMI's `_emiReminderOffsets`
/// exactly: 7/3 days before (due soon), the day of (due today), and 1/3 days
/// after (overdue, negative offsets — see
/// `ReminderNotificationService.reschedule`'s doc comment). Applies to both
/// repayment types: an installment loan's "next due date" is its next
/// unpaid installment; a one-time loan's is simply [Loan.dueDate] itself.
/// No per-loan picker in this milestone, same posture as EMI.
const _loanReminderOffsets = [7, 3, 1, 0, -1, -3];

/// Loan-specific persistence on top of the generic CRUD/soft-delete
/// repository. Bridges the feature-agnostic `PaymentScheduleRepository`/
/// `InstallmentRepository` (payment tracking) and `InterestCalculator`
/// (interest math) — neither of those core engines knows what a "loan" is;
/// this repository is where the two are composed.
class LoanRepository extends FirestoreCrudRepository<Loan> {
  LoanRepository(
    super.collection,
    this.paymentScheduleRepository,
    this._installmentRepositoryFor,
  );

  final PaymentScheduleRepository paymentScheduleRepository;

  /// Resolves an `InstallmentRepository` scoped to a given schedule id —
  /// installment collections are schedule-scoped, so this is supplied by
  /// the provider layer (which owns Riverpod's per-schedule repository
  /// instances) rather than constructed directly here.
  final InstallmentRepository Function(String scheduleId)
  _installmentRepositoryFor;

  Future<Loan> createLoan({
    required double loanAmount,
    required DateTime loanDate,
    required LoanRepaymentType repaymentType,
    String? personId,
    LoanDirection direction = LoanDirection.given,
    LoanCategory category = LoanCategory.personal,
    String? institutionName,
    String? loanType,
    String? loanNumber,
    String? accountNumber,
    String? branch,
    String? payerPersonId,
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
    if (category == LoanCategory.personal &&
        (personId == null || personId.isEmpty)) {
      throw const AppException('Choose a person');
    }
    if (category == LoanCategory.institutional &&
        (institutionName == null || institutionName.trim().isEmpty)) {
      throw const AppException('Institution name is required');
    }
    if (repaymentType == LoanRepaymentType.oneTime && dueDate == null) {
      throw const AppException('One-time loans need a due date');
    }
    if (repaymentType == LoanRepaymentType.installment) {
      if (installmentFrequency == null) {
        throw const AppException(
          'Monthly payment loans need a repayment frequency',
        );
      }
      if (installmentCount == null || installmentCount < 1) {
        throw const AppException(
          'Monthly payment loans need at least 1 payment',
        );
      }
    }
    if (interest != null && interest.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }

    // An institutional loan is never person-linked, regardless of what's
    // passed — structurally prevents the invalid "both" combination rather
    // than relying on the caller/UI alone.
    final effectivePersonId = category == LoanCategory.personal
        ? personId
        : null;

    final effectiveInstallmentCount = repaymentType == LoanRepaymentType.oneTime
        ? 1
        : installmentCount!;
    final effectiveScheduleType = repaymentType == LoanRepaymentType.oneTime
        ? ScheduleType.oneTime
        : installmentFrequency!;

    List<PrecomputedInstallmentAmount>? precomputed;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: loanAmount,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: effectiveInstallmentCount,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(effectiveScheduleType),
      );
      precomputed = breakdown.periods
          .map(
            (p) => PrecomputedInstallmentAmount(
              amountDue: p.paymentAmount,
              principalPortion: p.principalPortion,
              interestPortion: p.interestPortion,
            ),
          )
          .toList();
    }

    final loanId = IdGenerator.generate();
    final totalAmount = precomputed == null
        ? loanAmount
        : precomputed.fold(0.0, (sum, p) => sum + p.amountDue);

    final schedule = await paymentScheduleRepository.createSchedule(
      ownerType: OwnerType.loan,
      ownerId: loanId,
      totalAmount: totalAmount,
      scheduleType: effectiveScheduleType,
      firstDueDate: repaymentType == LoanRepaymentType.oneTime
          ? dueDate!
          : loanDate,
      installmentCount: effectiveInstallmentCount,
    );

    final installments = await _installmentRepositoryFor(
      schedule.id,
    ).generateInstallments(
      schedule,
      precomputedAmounts: precomputed,
      dueDayOfMonth: loanDate.day,
    );

    final loan = Loan(
      id: loanId,
      personId: effectivePersonId,
      direction: direction,
      category: category,
      institutionName: category == LoanCategory.institutional
          ? institutionName!.trim()
          : null,
      loanType: category == LoanCategory.institutional ? loanType : null,
      loanNumber: category == LoanCategory.institutional ? loanNumber : null,
      accountNumber: category == LoanCategory.institutional
          ? accountNumber
          : null,
      branch: category == LoanCategory.institutional ? branch : null,
      payerPersonId: payerPersonId,
      name: name,
      loanAmount: loanAmount,
      interest: interest,
      loanDate: loanDate,
      repaymentType: repaymentType,
      dueDate: repaymentType == LoanRepaymentType.oneTime ? dueDate : null,
      installmentFrequency: repaymentType == LoanRepaymentType.installment
          ? installmentFrequency
          : null,
      installmentCount: repaymentType == LoanRepaymentType.installment
          ? installmentCount
          : null,
      notes: notes,
      scheduleId: schedule.id,
      createdAt: DateTime.now(),
    );
    await add(loan.id, loan);
    if (installments.isNotEmpty) _scheduleReminders(loan, installments.first.dueDate);
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
    String? institutionName,
    String? loanType,
    String? loanNumber,
    String? accountNumber,
    String? branch,
    String? payerPersonId,
  }) async {
    if (loanAmount != null) {
      if (loanAmount <= 0) {
        throw const AppException('Loan amount must be greater than 0');
      }
      if (hasPayments) {
        throw const AppException(
          'Loan amount cannot be changed after a payment has been recorded',
        );
      }
    }
    if (dueDate != null && loan.repaymentType != LoanRepaymentType.oneTime) {
      throw const AppException('Only one-time loans have an editable due date');
    }

    loan.updateField(
      field: 'name',
      oldValue: loan.name,
      newValue: name,
      apply: (v) => loan.name = v,
    );
    loan.updateField(
      field: 'loanAmount',
      oldValue: loan.loanAmount,
      newValue: loanAmount,
      apply: (v) => loan.loanAmount = v,
    );
    loan.updateField(
      field: 'notes',
      oldValue: loan.notes,
      newValue: notes,
      apply: (v) => loan.notes = v,
    );
    loan.updateField(
      field: 'institutionName',
      oldValue: loan.institutionName,
      newValue: institutionName,
      apply: (v) => loan.institutionName = v,
    );
    loan.updateField(
      field: 'loanType',
      oldValue: loan.loanType,
      newValue: loanType,
      apply: (v) => loan.loanType = v,
    );
    loan.updateField(
      field: 'loanNumber',
      oldValue: loan.loanNumber,
      newValue: loanNumber,
      apply: (v) => loan.loanNumber = v,
    );
    loan.updateField(
      field: 'accountNumber',
      oldValue: loan.accountNumber,
      newValue: accountNumber,
      apply: (v) => loan.accountNumber = v,
    );
    loan.updateField(
      field: 'branch',
      oldValue: loan.branch,
      newValue: branch,
      apply: (v) => loan.branch = v,
    );
    loan.updateField(
      field: 'payerPersonId',
      oldValue: loan.payerPersonId,
      newValue: payerPersonId,
      apply: (v) => loan.payerPersonId = v,
    );
    await update(loan);
  }

  /// Changes [interest]/[installmentFrequency]/[installmentCount] on an
  /// installment loan that may already have payments recorded against it.
  /// Mirrors `EmiRepository.editEmiTerms` exactly: re-amortizes the
  /// *outstanding* principal (principal already paid down, via fully- or
  /// partially-paid installments, is left alone) over the new terms and
  /// regenerates only the untouched (zero-payment) tail of the schedule.
  /// One-time loans have no "terms" of this kind — the caller should never
  /// invoke this for a [LoanRepaymentType.oneTime] loan.
  ///
  /// [currentInstallments] must be every installment currently on
  /// `loan.scheduleId`. [newInstallmentCount] must be at least the number of
  /// installments that already carry a payment.
  Future<void> editLoanTerms(
    Loan loan, {
    required List<Installment> currentInstallments,
    LoanInterest? interest,
    ScheduleType? installmentFrequency,
    required int newInstallmentCount,
  }) async {
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException('Only installment loans have editable terms');
    }
    if (newInstallmentCount < 1) {
      throw const AppException('Loan needs at least 1 payment');
    }
    if (interest != null && interest.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }

    final sorted = [...currentInstallments]
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final settled = sorted
        .where((i) => i.amountPaid > 0 || i.isSkipped)
        .toList();
    final untouched = sorted
        .where((i) => i.amountPaid == 0 && !i.isSkipped)
        .toList();

    if (newInstallmentCount < settled.length) {
      throw const AppException(
        'Number of payments can\'t be less than the payments already made',
      );
    }

    final principalPaid = settled.fold(0.0, (sum, i) {
      if (i.amountPaid <= 0) return sum;
      final principalShare = i.principalPortion ?? i.amountDue;
      // A fully-paid installment counts its whole principal share. One
      // that's only partially paid (including a partial payment later
      // skipped) counts only the principal fraction of what was actually
      // paid — crediting the full share here would overstate principal
      // paid down and understate outstandingPrincipal below.
      if (i.amountPaid >= i.amountDue) return sum + principalShare;
      return sum + principalShare * (i.amountPaid / i.amountDue);
    });
    final outstandingPrincipal = (loan.loanAmount - principalPaid)
        .clamp(0, loan.loanAmount)
        .toDouble();
    final remainingCount = newInstallmentCount - settled.length;

    final effectiveFrequency =
        installmentFrequency ?? loan.installmentFrequency!;

    List<Installment> newTail = const [];
    if (remainingCount > 0 && outstandingPrincipal > 0) {
      List<PrecomputedInstallmentAmount>? precomputed;
      if (interest != null) {
        final breakdown = InterestCalculator.calculate(
          principal: outstandingPrincipal,
          type: interest.type,
          ratePercent: interest.ratePercent,
          period: interest.period,
          installmentCount: remainingCount,
          installmentFrequency: InterestPeriod.monthly,
          installmentsPerYear: _installmentsPerYearFor(effectiveFrequency),
        );
        precomputed = breakdown.periods
            .map(
              (p) => PrecomputedInstallmentAmount(
                amountDue: p.paymentAmount,
                principalPortion: p.principalPortion,
                interestPortion: p.interestPortion,
              ),
            )
            .toList();
      }

      final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
      await installmentRepository.replaceUnpaid(untouched);

      final lastSettled = settled.isEmpty ? null : settled.last;
      final nextDueDate = lastSettled == null
          ? effectiveFrequency.nextDueDate(loan.loanDate)
          : effectiveFrequency.nextDueDate(lastSettled.dueDate);
      final tailTotal = precomputed == null
          ? outstandingPrincipal
          : precomputed.fold(0.0, (s, p) => s + p.amountDue);

      final tailScheduleShape = PaymentSchedule(
        id: loan.scheduleId,
        ownerType: OwnerType.loan,
        ownerId: loan.id,
        totalAmount: tailTotal,
        scheduleType: effectiveFrequency,
        firstDueDate: nextDueDate,
        installmentCount: remainingCount,
        createdAt: DateTime.now(),
      );
      newTail = await installmentRepository.generateInstallments(
        tailScheduleShape,
        precomputedAmounts: precomputed,
        startingSequenceNumber: settled.length,
        dueDayOfMonth: loan.loanDate.day,
      );
    }

    loan.recordEdit(
      field: 'loanTerms',
      oldValue:
          '${loan.interest?.ratePercent}/${loan.installmentFrequency?.name}/${loan.installmentCount}',
      newValue:
          '${interest?.ratePercent}/${effectiveFrequency.name}/$newInstallmentCount',
    );
    loan.interest = interest;
    loan.installmentFrequency = effectiveFrequency;
    loan.installmentCount = newInstallmentCount;
    await update(loan);

    final schedule = await paymentScheduleRepository.getByKey(loan.scheduleId);
    if (schedule != null) {
      final settledTotal = settled.fold(0.0, (sum, i) => sum + i.amountDue);
      final newTailTotal = newTail.fold(0.0, (sum, i) => sum + i.amountDue);
      await paymentScheduleRepository.editSchedule(
        schedule,
        installmentCount: newInstallmentCount,
        totalAmount: settledTotal + newTailTotal,
      );
    }

    if (newTail.isNotEmpty) {
      rescheduleReminders(loan, newTail.first.dueDate);
    } else {
      _cancelReminders(loan.id);
    }
  }

  /// Changes [Loan.loanDate] ("Loan Date") for an installment loan — only
  /// permitted before any payment exists anywhere on the loan, mirroring
  /// `EmiRepository.editStartDate`. Regenerates every installment from
  /// scratch against the new date, reusing the loan's existing
  /// interest/frequency/count. One-time loans use [dueDate] instead, which
  /// is already editable via [editLoan].
  Future<void> editLoanDate(
    Loan loan, {
    required DateTime newLoanDate,
    required bool hasPayments,
    required List<Installment> currentInstallments,
  }) async {
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException(
        'Only installment loans have an editable loan date',
      );
    }
    if (hasPayments) {
      throw const AppException(
        'Loan date can\'t be changed after a payment has been recorded',
      );
    }

    final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
    for (final installment in currentInstallments) {
      await installmentRepository.softDelete(installment);
    }

    List<PrecomputedInstallmentAmount>? precomputed;
    final interest = loan.interest;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: loan.loanAmount,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: loan.installmentCount!,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(
          loan.installmentFrequency!,
        ),
      );
      precomputed = breakdown.periods
          .map(
            (p) => PrecomputedInstallmentAmount(
              amountDue: p.paymentAmount,
              principalPortion: p.principalPortion,
              interestPortion: p.interestPortion,
            ),
          )
          .toList();
    }

    final schedule = await paymentScheduleRepository.getByKey(loan.scheduleId);
    final totalAmount = precomputed == null
        ? loan.loanAmount
        : precomputed.fold(0.0, (sum, p) => sum + p.amountDue);
    if (schedule != null) {
      await paymentScheduleRepository.editSchedule(
        schedule,
        totalAmount: totalAmount,
        firstDueDate: newLoanDate,
      );
    }

    final newInstallments = await installmentRepository.generateInstallments(
      PaymentSchedule(
        id: loan.scheduleId,
        ownerType: OwnerType.loan,
        ownerId: loan.id,
        totalAmount: totalAmount,
        scheduleType: loan.installmentFrequency!,
        firstDueDate: newLoanDate,
        installmentCount: loan.installmentCount!,
        createdAt: loan.createdAt,
      ),
      precomputedAmounts: precomputed,
      dueDayOfMonth: newLoanDate.day,
    );

    loan.recordEdit(
      field: 'loanDate',
      oldValue: loan.loanDate.toIso8601String(),
      newValue: newLoanDate.toIso8601String(),
    );
    loan.loanDate = newLoanDate;
    await update(loan);

    if (newInstallments.isNotEmpty) rescheduleReminders(loan, newInstallments.first.dueDate);
  }

  Future<void> closeLoan(Loan loan) async {
    if (loan.isClosed) return;
    loan.recordEdit(field: 'isClosed', oldValue: 'false', newValue: 'true');
    loan.isClosed = true;
    await update(loan);
    _cancelReminders(loan.id);
  }

  /// [currentInstallments] lets a still-unpaid installment loan pick back up
  /// its reminders against its next unpaid due date; a one-time loan (no
  /// installments) reschedules against [Loan.dueDate] itself. Optional and
  /// defaults to empty so existing call sites that don't have the list on
  /// hand keep compiling — they simply won't get reminders restored until
  /// the next payment/edit touches this loan.
  Future<void> reopenLoan(Loan loan, {List<Installment> currentInstallments = const []}) async {
    if (!loan.isClosed) return;
    loan.recordEdit(field: 'isClosed', oldValue: 'true', newValue: 'false');
    loan.isClosed = false;
    await update(loan);

    if (loan.repaymentType == LoanRepaymentType.oneTime) {
      if (loan.dueDate != null) _scheduleReminders(loan, loan.dueDate!);
      return;
    }
    final nextUnpaid = currentInstallments.where((i) => i.remainingAmount > 0 && !i.isSkipped).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (nextUnpaid.isNotEmpty) rescheduleReminders(loan, nextUnpaid.first.dueDate);
  }

  /// Wipes [loan] and everything under it — unlike the generic inherited
  /// `permanentlyDelete` (which only removes the `loans/{loanId}` doc), this
  /// also deletes every `Installment` on the linked schedule (including
  /// already-trashed ones from a prior `editLoanTerms`/`editLoanDate`
  /// regeneration), each installment's own `payments` subcollection, and the
  /// `PaymentSchedule` document — so nothing orphaned is left in Firestore,
  /// and any reminder still scheduled against this loan is cancelled too.
  /// Mirrors `EmiRepository.permanentlyDeleteEmi` exactly. This is the
  /// method trash screens should call instead of the inherited
  /// `permanentlyDelete`.
  Future<void> permanentlyDeleteLoan(Loan loan) async {
    final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
    final installments = await installmentRepository.getAll();
    final trashedInstallments = await installmentRepository.getTrash();

    for (final installment in [...installments, ...trashedInstallments]) {
      final paymentsSnapshot =
          await installmentRepository.collection.doc(installment.id).collection(FirestoreCollections.payments).get();
      for (final paymentDoc in paymentsSnapshot.docs) {
        await paymentDoc.reference.delete();
      }
      await installmentRepository.permanentlyDelete(installment);
    }

    _cancelReminders(loan.id);

    await paymentScheduleRepository.collection.doc(loan.scheduleId).delete();
    await permanentlyDelete(loan);
  }

  /// Reschedules reminders against [nextDueDate] — the caller resolves this
  /// from the loan's next unpaid installment (installment loans) or its own
  /// [Loan.dueDate] (one-time loans). Exposed publicly (unlike Bills'
  /// private `_scheduleReminders`) because a loan's "next due date" changes
  /// on every payment, not just on create/edit, so the payment-recording UI
  /// needs to trigger this too — mirrors `EmiRepository.rescheduleReminders`.
  void rescheduleReminders(Loan loan, DateTime nextDueDate) => _scheduleReminders(loan, nextDueDate);

  /// Cancels every reminder scheduled for [loanId] — call once a loan has
  /// nothing left to remind about (fully paid off, but not explicitly
  /// closed). Public so payment-recording UIs can call it directly when a
  /// payment leaves no unpaid installment behind, same as [rescheduleReminders].
  void cancelReminders(String loanId) => _cancelReminders(loanId);

  /// Best-effort, fire-and-forget — a notification scheduling failure must
  /// never block or fail a Firestore write, and the installment schedule
  /// stays the sole source of truth regardless of whether this succeeds.
  void _scheduleReminders(Loan loan, DateTime nextDueDate) {
    final label = loan.repaymentType == LoanRepaymentType.oneTime ? 'loan payment' : 'EMI';
    ReminderNotificationService.reschedule(
      ownerId: loan.id,
      title: loan.name?.isNotEmpty == true ? loan.name! : 'Loan',
      bodyBuilder: (offset) => '${reminderOffsetLabel(offset)} — $label due ${nextDueDate.day}/${nextDueDate.month}',
      dueDate: nextDueDate,
      offsets: _loanReminderOffsets,
    ).catchError((_) {});
  }

  void _cancelReminders(String loanId) {
    ReminderNotificationService.cancel(loanId).catchError((_) {});
  }

  /// True per-installment count for [InterestCalculator]'s
  /// [installmentsPerYear] rate normalization — weekly gets its own exact
  /// value (52) instead of being forced through the monthly bucket, which
  /// previously overstated weekly interest by ~4.3x. `oneTime` never
  /// reaches [InterestCalculator]'s periodic-rate path (a single
  /// installment uses the quoted rate directly), so its value here is
  /// unused; `custom` isn't offered by the Loans form, so 12 (monthly) is
  /// a safe placeholder if that ever changes.
  int _installmentsPerYearFor(ScheduleType scheduleType) {
    switch (scheduleType) {
      case ScheduleType.weekly:
        return 52;
      case ScheduleType.monthly:
      case ScheduleType.oneTime:
      case ScheduleType.custom:
        return 12;
    }
  }
}
