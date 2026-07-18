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
import '../domain/emi.dart';
import '../domain/emi_interest.dart';
import '../domain/emi_loan_type.dart';

/// Fixed reminder offsets for EMI (Due Today, 1/3/7 days before) — no
/// per-EMI picker in this milestone, unlike Bills' configurable `FilterChip`
/// offsets.
const _emiReminderOffsets = [0, 1, 3, 7];

/// Reminder offsets for the "loan ending soon" one-time reminder, scheduled
/// against the last installment's due date under a distinct owner id so it
/// doesn't collide with (or get cancelled by) the regular per-installment
/// reminders above.
const _emiEndingReminderOffsets = [7, 1];

/// EMI-specific persistence on top of the generic CRUD/soft-delete
/// repository. Bridges the feature-agnostic `PaymentScheduleRepository`/
/// `InstallmentRepository` (payment tracking) and `InterestCalculator`
/// (interest math) — neither of those core engines knows what an "EMI" is;
/// this repository is where the two are composed, mirroring `LoanRepository`.
class EmiRepository extends FirestoreCrudRepository<Emi> {
  EmiRepository(super.collection, this.paymentScheduleRepository, this._installmentRepositoryFor);

  final PaymentScheduleRepository paymentScheduleRepository;

  /// Resolves an `InstallmentRepository` scoped to a given schedule id —
  /// supplied by the provider layer, mirrors `LoanRepository`'s dependency
  /// shape exactly.
  final InstallmentRepository Function(String scheduleId) _installmentRepositoryFor;

  Future<Emi> createEmi({
    required String name,
    required double principalAmount,
    required DateTime startDate,
    required ScheduleType installmentFrequency,
    required int installmentCount,
    String? lenderName,
    String? categoryId,
    EmiInterest? interest,
    String notes = '',
    String? loanNumber,
    EmiLoanType loanType = EmiLoanType.other,
    String? branch,
    String? customerId,
    DateTime? sanctionDate,
    DateTime? disbursementDate,
    double processingFee = 0,
    double insuranceAmount = 0,
    double extraCharges = 0,
    double? foreclosureAmount,
    double? prepaymentCharges,
    bool isAutoDebitEnabled = false,
    String? autoDebitAccount,
    String? linkedCreditCardId,
    int? dueDayOfMonth,
  }) async {
    if (name.trim().isEmpty) {
      throw const AppException('EMI name is required');
    }
    if (principalAmount <= 0) {
      throw const AppException('Principal amount must be greater than 0');
    }
    if (installmentCount < 1) {
      throw const AppException('EMI needs at least 1 installment');
    }
    if (interest != null && interest.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }
    if (dueDayOfMonth != null && (dueDayOfMonth < 1 || dueDayOfMonth > 31)) {
      throw const AppException('Monthly due date must be between 1 and 31');
    }

    List<PrecomputedInstallmentAmount>? precomputed;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: principalAmount,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: installmentCount,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(installmentFrequency),
      );
      precomputed = breakdown.periods
          .map((p) => PrecomputedInstallmentAmount(
                amountDue: p.paymentAmount,
                principalPortion: p.principalPortion,
                interestPortion: p.interestPortion,
              ))
          .toList();
    }

    final emiId = IdGenerator.generate();
    final totalAmount = precomputed == null ? principalAmount : precomputed.fold(0.0, (sum, p) => sum + p.amountDue);

    final schedule = await paymentScheduleRepository.createSchedule(
      ownerType: OwnerType.emi,
      ownerId: emiId,
      totalAmount: totalAmount,
      scheduleType: installmentFrequency,
      firstDueDate: startDate,
      installmentCount: installmentCount,
    );

    final installments = await _installmentRepositoryFor(schedule.id).generateInstallments(
      schedule,
      precomputedAmounts: precomputed,
      dueDayOfMonth: dueDayOfMonth,
    );

    final emi = Emi(
      id: emiId,
      name: name,
      lenderName: lenderName,
      categoryId: categoryId,
      principalAmount: principalAmount,
      interest: interest,
      startDate: startDate,
      installmentFrequency: installmentFrequency,
      installmentCount: installmentCount,
      endDate: installments.last.dueDate,
      notes: notes,
      scheduleId: schedule.id,
      createdAt: DateTime.now(),
      loanNumber: loanNumber,
      loanType: loanType,
      branch: branch,
      customerId: customerId,
      sanctionDate: sanctionDate,
      disbursementDate: disbursementDate,
      processingFee: processingFee,
      insuranceAmount: insuranceAmount,
      extraCharges: extraCharges,
      foreclosureAmount: foreclosureAmount,
      prepaymentCharges: prepaymentCharges,
      isAutoDebitEnabled: isAutoDebitEnabled,
      autoDebitAccount: autoDebitAccount,
      linkedCreditCardId: linkedCreditCardId,
      dueDayOfMonth: dueDayOfMonth,
    );
    await add(emi.id, emi);
    _scheduleReminders(emi, installments.first.dueDate);
    _scheduleEndingReminder(emi);
    return emi;
  }

  /// [name]/[lenderName]/[categoryId]/[notes] and the bank/charges metadata
  /// fields below are editable post-creation. [principalAmount] locks once
  /// [hasPayments] is true (mirrors `LoanRepository.editLoan`'s posture).
  /// [interest]/[installmentFrequency]/[installmentCount] are edited
  /// through [editEmiTerms] instead, which regenerates the unpaid tail of
  /// the schedule; [startDate] stays immutable (it seeds the schedule's
  /// `firstDueDate`, which only matters for the very first installment).
  Future<void> editEmi(
    Emi emi, {
    required bool hasPayments,
    String? name,
    String? lenderName,
    String? categoryId,
    double? principalAmount,
    String? notes,
    String? loanNumber,
    EmiLoanType? loanType,
    String? branch,
    String? customerId,
    DateTime? sanctionDate,
    DateTime? disbursementDate,
    double? processingFee,
    double? insuranceAmount,
    double? extraCharges,
    double? foreclosureAmount,
    double? prepaymentCharges,
    bool? isAutoDebitEnabled,
    String? autoDebitAccount,
    String? linkedCreditCardId,
    bool clearLinkedCreditCardId = false,
  }) async {
    if (principalAmount != null) {
      if (principalAmount <= 0) {
        throw const AppException('Principal amount must be greater than 0');
      }
      if (hasPayments) {
        throw const AppException('Principal amount cannot be changed after a payment has been recorded');
      }
    }

    emi.updateField(field: 'name', oldValue: emi.name, newValue: name, apply: (v) => emi.name = v);
    emi.updateField(
      field: 'lenderName',
      oldValue: emi.lenderName,
      newValue: lenderName,
      apply: (v) => emi.lenderName = v,
    );
    emi.updateField(
      field: 'categoryId',
      oldValue: emi.categoryId,
      newValue: categoryId,
      apply: (v) => emi.categoryId = v,
    );
    emi.updateField(
      field: 'principalAmount',
      oldValue: emi.principalAmount,
      newValue: principalAmount,
      apply: (v) => emi.principalAmount = v,
    );
    emi.updateField(field: 'notes', oldValue: emi.notes, newValue: notes, apply: (v) => emi.notes = v);
    emi.updateField(
      field: 'loanNumber',
      oldValue: emi.loanNumber,
      newValue: loanNumber,
      apply: (v) => emi.loanNumber = v,
    );
    emi.updateField(
      field: 'loanType',
      oldValue: emi.loanType.name,
      newValue: loanType?.name,
      apply: (_) => emi.loanType = loanType!,
    );
    emi.updateField(field: 'branch', oldValue: emi.branch, newValue: branch, apply: (v) => emi.branch = v);
    emi.updateField(
      field: 'customerId',
      oldValue: emi.customerId,
      newValue: customerId,
      apply: (v) => emi.customerId = v,
    );
    emi.updateField(
      field: 'sanctionDate',
      oldValue: emi.sanctionDate?.toIso8601String(),
      newValue: sanctionDate?.toIso8601String(),
      apply: (_) => emi.sanctionDate = sanctionDate,
    );
    emi.updateField(
      field: 'disbursementDate',
      oldValue: emi.disbursementDate?.toIso8601String(),
      newValue: disbursementDate?.toIso8601String(),
      apply: (_) => emi.disbursementDate = disbursementDate,
    );
    emi.updateField(
      field: 'processingFee',
      oldValue: emi.processingFee,
      newValue: processingFee,
      apply: (v) => emi.processingFee = v,
    );
    emi.updateField(
      field: 'insuranceAmount',
      oldValue: emi.insuranceAmount,
      newValue: insuranceAmount,
      apply: (v) => emi.insuranceAmount = v,
    );
    emi.updateField(
      field: 'extraCharges',
      oldValue: emi.extraCharges,
      newValue: extraCharges,
      apply: (v) => emi.extraCharges = v,
    );
    emi.updateField(
      field: 'foreclosureAmount',
      oldValue: emi.foreclosureAmount,
      newValue: foreclosureAmount,
      apply: (v) => emi.foreclosureAmount = v,
    );
    emi.updateField(
      field: 'prepaymentCharges',
      oldValue: emi.prepaymentCharges,
      newValue: prepaymentCharges,
      apply: (v) => emi.prepaymentCharges = v,
    );
    emi.updateField(
      field: 'isAutoDebitEnabled',
      oldValue: emi.isAutoDebitEnabled,
      newValue: isAutoDebitEnabled,
      apply: (v) => emi.isAutoDebitEnabled = v,
    );
    emi.updateField(
      field: 'autoDebitAccount',
      oldValue: emi.autoDebitAccount,
      newValue: autoDebitAccount,
      apply: (v) => emi.autoDebitAccount = v,
    );
    if (clearLinkedCreditCardId) {
      emi.recordEdit(
        field: 'linkedCreditCardId',
        oldValue: emi.linkedCreditCardId ?? 'none',
        newValue: 'none',
      );
      emi.linkedCreditCardId = null;
    } else {
      emi.updateField(
        field: 'linkedCreditCardId',
        oldValue: emi.linkedCreditCardId,
        newValue: linkedCreditCardId,
        apply: (v) => emi.linkedCreditCardId = v,
      );
    }
    await update(emi);
  }

  /// Changes [interest]/[installmentFrequency]/[installmentCount] on an
  /// EMI that may already have payments recorded against it. Unlike
  /// [editEmi]'s other fields, these drive the installment schedule, so
  /// this doesn't just overwrite the `Emi` document — it re-amortizes the
  /// *outstanding* principal (principal already paid down, via fully- or
  /// partially-paid installments, is left alone) over the new terms and
  /// regenerates only the untouched (zero-payment) tail of the schedule.
  ///
  /// [currentInstallments] must be every installment currently on
  /// `emi.scheduleId` (the caller already has this stream watched).
  /// [newInstallmentCount] must be at least the number of installments that
  /// already carry a payment (fully or partially paid) — you can't shrink
  /// the schedule below what's already been paid for.
  Future<void> editEmiTerms(
    Emi emi, {
    required List<Installment> currentInstallments,
    EmiInterest? interest,
    ScheduleType? installmentFrequency,
    required int newInstallmentCount,
    int? dueDayOfMonth,
  }) async {
    if (newInstallmentCount < 1) {
      throw const AppException('EMI needs at least 1 installment');
    }
    if (interest != null && interest.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }
    if (dueDayOfMonth != null && (dueDayOfMonth < 1 || dueDayOfMonth > 31)) {
      throw const AppException('Monthly due date must be between 1 and 31');
    }

    final sorted = [...currentInstallments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final settled = sorted.where((i) => i.amountPaid > 0 || i.isSkipped).toList();
    final untouched = sorted.where((i) => i.amountPaid == 0 && !i.isSkipped).toList();

    if (newInstallmentCount < settled.length) {
      throw const AppException('Number of payments can\'t be less than the payments already made');
    }

    // Principal already paid down: for interest-bearing installments, only
    // the principalPortion counts (interest already paid isn't principal);
    // for non-interest ones, the whole amountPaid is principal.
    final principalPaid = settled.fold(0.0, (sum, i) {
      if (i.isSkipped && i.amountPaid == 0) return sum;
      return sum + (i.principalPortion ?? i.amountPaid);
    });
    final outstandingPrincipal = (emi.principalAmount - principalPaid).clamp(0, emi.principalAmount).toDouble();
    final remainingCount = newInstallmentCount - settled.length;

    final effectiveFrequency = installmentFrequency ?? emi.installmentFrequency;

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
            .map((p) => PrecomputedInstallmentAmount(
                  amountDue: p.paymentAmount,
                  principalPortion: p.principalPortion,
                  interestPortion: p.interestPortion,
                ))
            .toList();
      }

      final installmentRepository = _installmentRepositoryFor(emi.scheduleId);
      await installmentRepository.replaceUnpaid(untouched);

      final effectiveDueDayOfMonth = dueDayOfMonth ?? emi.dueDayOfMonth;
      final lastSettled = settled.isEmpty ? null : settled.last;
      var nextDueDate = lastSettled == null
          ? effectiveFrequency.nextDueDate(emi.startDate)
          : effectiveFrequency.nextDueDate(lastSettled.dueDate);
      // Unlike `createEmi`'s installment #1 (always the real First EMI
      // Date), the tail's first installment here is a *continuation* of an
      // existing EMI, not a fresh "first payment" — so when a due day is
      // set, it snaps too, same as every installment after it. Only
      // installment #1 of the EMI as a whole (still intact among `settled`
      // or, if nothing's settled yet, `emi.startDate` itself) is ever
      // exempt from this snapping.
      if (effectiveDueDayOfMonth != null && effectiveFrequency == ScheduleType.monthly && lastSettled != null) {
        final lastDayOfMonth = DateTime(nextDueDate.year, nextDueDate.month + 1, 0).day;
        final snappedDay = effectiveDueDayOfMonth > lastDayOfMonth ? lastDayOfMonth : effectiveDueDayOfMonth;
        nextDueDate = DateTime(nextDueDate.year, nextDueDate.month, snappedDay);
      }
      final tailTotal = precomputed == null ? outstandingPrincipal : precomputed.fold(0.0, (s, p) => s + p.amountDue);

      // In-memory only (never persisted as its own document) — just a
      // parameter object so `generateInstallments` can compute due dates
      // and stamp every new installment with the EMI's real scheduleId.
      final tailScheduleShape = PaymentSchedule(
        id: emi.scheduleId,
        ownerType: OwnerType.emi,
        ownerId: emi.id,
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
        dueDayOfMonth: effectiveDueDayOfMonth,
      );
    }

    emi.recordEdit(
      field: 'loanTerms',
      oldValue: '${emi.interest?.ratePercent}/${emi.installmentFrequency.name}/${emi.installmentCount}',
      newValue: '${interest?.ratePercent}/${effectiveFrequency.name}/$newInstallmentCount',
    );
    emi.interest = interest;
    emi.installmentFrequency = effectiveFrequency;
    emi.installmentCount = newInstallmentCount;
    emi.dueDayOfMonth = dueDayOfMonth ?? emi.dueDayOfMonth;
    emi.endDate = newTail.isNotEmpty ? newTail.last.dueDate : (settled.isEmpty ? emi.startDate : settled.last.dueDate);
    await update(emi);

    final schedule = await paymentScheduleRepository.getByKey(emi.scheduleId);
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
      rescheduleReminders(emi, newTail.first.dueDate);
    }
    _scheduleEndingReminder(emi);
  }

  Future<void> closeEmi(Emi emi) async {
    if (emi.isClosed) return;
    emi.recordEdit(field: 'isClosed', oldValue: 'false', newValue: 'true');
    emi.isClosed = true;
    await update(emi);
    _cancelReminders(emi.id);
    _cancelEndingReminder(emi.id);
  }

  /// Marks an EMI as defaulted — an explicit user action distinct from
  /// "overdue" (a derived, automatically-clearing state); mirrors
  /// [closeEmi]/[reopenEmi]'s audit-trail posture. Doesn't touch reminders:
  /// a defaulted loan still has real installments the user may want
  /// reminders about.
  Future<void> markDefaulted(Emi emi) async {
    if (emi.isDefaulted) return;
    emi.recordEdit(field: 'isDefaulted', oldValue: 'false', newValue: 'true');
    emi.isDefaulted = true;
    await update(emi);
  }

  Future<void> clearDefaulted(Emi emi) async {
    if (!emi.isDefaulted) return;
    emi.recordEdit(field: 'isDefaulted', oldValue: 'true', newValue: 'false');
    emi.isDefaulted = false;
    await update(emi);
  }

  /// Early closure with an outstanding balance: soft-deletes every
  /// not-fully-paid installment in [installments] (shortening the schedule
  /// to what was actually paid — see `InstallmentRepository.closeOutRemaining`)
  /// before closing the EMI. Use plain [closeEmi] when every installment is
  /// already fully paid; this variant is specifically for writing off a
  /// remaining balance.
  Future<void> closeEmiEarly(Emi emi, List<Installment> installments) async {
    if (emi.isClosed) return;
    await _installmentRepositoryFor(emi.scheduleId).closeOutRemaining(installments);
    await closeEmi(emi);
  }

  Future<void> reopenEmi(Emi emi) async {
    if (!emi.isClosed) return;
    emi.recordEdit(field: 'isClosed', oldValue: 'true', newValue: 'false');
    emi.isClosed = false;
    await update(emi);
  }

  /// Reschedules reminders against [nextDueDate] — the caller resolves this
  /// from the EMI's next unpaid installment. Exposed publicly (unlike
  /// Bills' private `_scheduleReminders`) because EMI's "next due date"
  /// changes on every payment, not just on create/edit, so the payment
  /// recording flow needs to trigger this too.
  void rescheduleReminders(Emi emi, DateTime nextDueDate) => _scheduleReminders(emi, nextDueDate);

  /// Best-effort, fire-and-forget — a notification scheduling failure must
  /// never block or fail a Firestore write.
  void _scheduleReminders(Emi emi, DateTime nextDueDate) {
    ReminderNotificationService.reschedule(
      ownerId: emi.id,
      title: emi.name,
      bodyBuilder: (offset) =>
          '${reminderOffsetLabel(offset)} — EMI due ${nextDueDate.day}/${nextDueDate.month}',
      dueDate: nextDueDate,
      offsets: _emiReminderOffsets,
    ).catchError((_) {});
  }

  void _cancelReminders(String emiId) {
    ReminderNotificationService.cancel(emiId).catchError((_) {});
  }

  /// One-time "loan ending soon" reminder against [Emi.endDate], scheduled
  /// under a distinct owner id (`'<emiId>_ending'`) so it doesn't collide
  /// with, or get cancelled alongside, the regular per-installment
  /// reminders scheduled under the plain EMI id. Best-effort, matching
  /// [_scheduleReminders].
  void _scheduleEndingReminder(Emi emi) {
    ReminderNotificationService.reschedule(
      ownerId: '${emi.id}_ending',
      title: emi.name,
      bodyBuilder: (offset) => '${reminderOffsetLabel(offset)} — loan ending soon',
      dueDate: emi.endDate,
      offsets: _emiEndingReminderOffsets,
    ).catchError((_) {});
  }

  void _cancelEndingReminder(String emiId) {
    ReminderNotificationService.cancel('${emiId}_ending').catchError((_) {});
  }

  /// True per-installment count for [InterestCalculator]'s
  /// [installmentsPerYear] rate normalization — weekly gets its own exact
  /// value (52) instead of being forced through the monthly bucket, which
  /// previously overstated weekly interest by ~4.3x. `custom` isn't
  /// offered by the EMI form, so 12 (monthly) is a safe placeholder if
  /// that ever changes; `oneTime` isn't a valid EMI installment frequency
  /// but is included for exhaustiveness.
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
