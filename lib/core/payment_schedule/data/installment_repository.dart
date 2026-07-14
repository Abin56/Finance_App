import '../../data/firestore_crud_repository.dart';
import '../../errors/app_exception.dart';
import '../../extensions/date_extensions.dart';
import '../../utils/id_generator.dart';
import '../domain/installment.dart';
import '../domain/installment_status.dart';
import '../domain/payment_schedule.dart';
import '../domain/precomputed_installment_amount.dart';
import '../domain/schedule_type.dart';

/// Installment persistence for one schedule's
/// `users/{uid}/paymentSchedules/{scheduleId}/installments` subcollection.
/// Constructed per-schedule (see `installmentRepositoryProvider`).
class InstallmentRepository extends FirestoreCrudRepository<Installment> {
  InstallmentRepository(super.collection);

  /// Materializes [schedule]'s installments. When [precomputedAmounts] is
  /// omitted, [PaymentSchedule.totalAmount] is split evenly across
  /// [PaymentSchedule.installmentCount] with the last installment absorbing
  /// the rounding remainder. When provided, its length must equal
  /// [PaymentSchedule.installmentCount] and each entry supplies that
  /// installment's exact amountDue plus optional principal/interest split —
  /// used by interest-bearing loans, where the caller has already run
  /// `InterestCalculator` and knows the exact per-installment figures. This
  /// keeps this engine fully ignorant of what "interest" is.
  ///
  /// [startingSequenceNumber] offsets every generated installment's
  /// [Installment.sequenceNumber] (default 0, i.e. numbering starts at 1) —
  /// used by `EmiRepository.editEmiTerms` to append a regenerated tail after
  /// installments that already exist on the same schedule, so sequence
  /// numbers stay contiguous instead of restarting at 1.
  ///
  /// [dueDayOfMonth] (1-31), when set on a [ScheduleType.monthly] schedule,
  /// pins every installment *after* the first to that fixed day of the
  /// month — installment #1 always stays exactly on [PaymentSchedule.firstDueDate]
  /// regardless of its own day, matching how a real EMI's first payment can
  /// fall any time but every payment after settles into a fixed monthly due
  /// day (e.g. "always the 5th"). Ignored for every other [ScheduleType]
  /// and when null (the default), in which case behavior is unchanged from
  /// before this parameter existed: each date chains off the previous
  /// installment's via [ScheduleType.nextDueDate].
  Future<List<Installment>> generateInstallments(
    PaymentSchedule schedule, {
    List<PrecomputedInstallmentAmount>? precomputedAmounts,
    int startingSequenceNumber = 0,
    int? dueDayOfMonth,
  }) async {
    final count = schedule.installmentCount;
    if (count == null || count < 1) {
      throw const AppException('Schedule needs at least 1 installment to generate');
    }
    if (precomputedAmounts != null && precomputedAmounts.length != count) {
      throw const AppException('precomputedAmounts must have one entry per installment');
    }

    final amounts = precomputedAmounts ?? _evenSplit(schedule.totalAmount, count);
    final pinToDueDay = dueDayOfMonth != null && schedule.scheduleType == ScheduleType.monthly;

    final installments = <Installment>[];
    var dueDate = schedule.firstDueDate;
    for (var i = 0; i < count; i++) {
      if (i > 0) {
        dueDate = pinToDueDay
            ? _addMonthsTargetingDay(schedule.firstDueDate, i, dueDayOfMonth)
            : schedule.scheduleType.nextDueDate(dueDate, customDays: schedule.customIntervalDays);
      }
      final installment = Installment(
        id: IdGenerator.generate(),
        scheduleId: schedule.id,
        ownerType: schedule.ownerType,
        ownerId: schedule.ownerId,
        sequenceNumber: startingSequenceNumber + i + 1,
        dueDate: dueDate,
        amountDue: amounts[i].amountDue,
        principalPortion: amounts[i].principalPortion,
        interestPortion: amounts[i].interestPortion,
        createdAt: DateTime.now(),
      );
      await add(installment.id, installment);
      installments.add(installment);
    }
    return installments;
  }

  /// Adds [monthsAhead] calendar months to [firstDueDate], then overrides
  /// the resulting day to [targetDay] — clamped to that target month's
  /// actual last day, same end-of-month rule as `ScheduleType._addMonths`
  /// (e.g. targeting the 31st in February lands on the 28th/29th). Computed
  /// from [firstDueDate] directly (not chained off the previous
  /// installment) so every installment lands on exactly [targetDay] with no
  /// drift, however many months are added.
  static DateTime _addMonthsTargetingDay(DateTime firstDueDate, int monthsAhead, int targetDay) {
    final targetMonthIndex = firstDueDate.month - 1 + monthsAhead;
    final targetYear = firstDueDate.year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final lastDayOfTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final day = targetDay > lastDayOfTargetMonth ? lastDayOfTargetMonth : targetDay;
    return DateTime(targetYear, targetMonth, day, firstDueDate.hour, firstDueDate.minute, firstDueDate.second);
  }

  List<PrecomputedInstallmentAmount> _evenSplit(double total, int count) {
    final share = _round2(total / count);
    final shares = List.filled(count, share);
    final remainder = _round2(total - share * count);
    shares[count - 1] = _round2(shares[count - 1] + remainder);
    return shares.map((amount) => PrecomputedInstallmentAmount(amountDue: amount)).toList();
  }

  double _round2(double v) => (v * 100).round() / 100;

  /// Applies a payment delta toward this installment, clamped so
  /// [Installment.amountPaid] never exceeds [Installment.amountDue] —
  /// mirrors `BillRepository.applyPayment`'s clamp + audit pattern, minus
  /// rollover (installments are fixed, distinct documents, not a rolling
  /// occurrence).
  Future<void> applyPayment(Installment installment, double delta) async {
    if (delta == 0) return;
    final newAmountPaid = (installment.amountPaid + delta).clamp(0, installment.amountDue).toDouble();
    installment.recordEdit(
      field: 'amountPaid',
      oldValue: installment.amountPaid.toString(),
      newValue: newAmountPaid.toString(),
    );
    installment.amountPaid = newAmountPaid;
    await update(installment);
  }

  /// Changes how much is owed on [installment] — used when editing a split
  /// expense's amount/shares after the fact. Guards against setting the new
  /// amount below what's already been collected, since that would silently
  /// erase a real payment; callers should surface this as a clear "already
  /// paid" error rather than letting it happen.
  Future<void> editInstallmentAmount(Installment installment, double newAmountDue) async {
    if (newAmountDue < installment.amountPaid) {
      throw const AppException('Cannot set an amount lower than what has already been paid');
    }
    if (newAmountDue == installment.amountDue) return;
    installment.recordEdit(
      field: 'amountDue',
      oldValue: installment.amountDue.toString(),
      newValue: newAmountDue.toString(),
    );
    installment.amountDue = newAmountDue;
    await update(installment);
  }

  /// Changes when [installment] is due — used when editing a split expense's
  /// due date after the fact. Unlike [editInstallmentAmount], there's
  /// nothing to guard against: pushing a due date earlier or later never
  /// conflicts with an already-recorded payment.
  Future<void> editInstallmentDueDate(Installment installment, DateTime newDueDate) async {
    if (newDueDate == installment.dueDate) return;
    installment.recordEdit(
      field: 'dueDate',
      oldValue: installment.dueDate.toIso8601String(),
      newValue: newDueDate.toIso8601String(),
    );
    installment.dueDate = newDueDate;
    await update(installment);
  }

  Future<void> skipInstallment(Installment installment) async {
    if (installment.isSkipped) return;
    installment.recordEdit(field: 'isSkipped', oldValue: 'false', newValue: 'true');
    installment.isSkipped = true;
    await update(installment);
  }

  Future<void> unskipInstallment(Installment installment) async {
    if (!installment.isSkipped) return;
    installment.recordEdit(field: 'isSkipped', oldValue: 'true', newValue: 'false');
    installment.isSkipped = false;
    await update(installment);
  }

  /// Early closure: soft-deletes every not-fully-paid installment in
  /// [remaining] so they drop out of `watchAll()`/`remainingAmount()` —
  /// the schedule is effectively shortened to whatever was actually paid,
  /// rather than left dangling as "upcoming"/"overdue" against a closed EMI.
  /// Fully paid installments are left untouched (nothing to close out).
  /// Returns the installments that were soft-deleted, for callers that need
  /// to reverse this (see `EmiRepository.reopenEmiEarlyClosure` in future,
  /// currently not exposed since reopening isn't in scope).
  Future<List<Installment>> closeOutRemaining(List<Installment> remaining) async {
    final toClose = remaining.where((i) => i.status != InstallmentStatus.paid).toList();
    for (final installment in toClose) {
      await softDelete(installment);
    }
    return toClose;
  }

  /// Soft-deletes every installment in [installments] with no payment
  /// recorded against it at all (`amountPaid == 0`) — used by
  /// `EmiRepository.editEmiTerms` to clear the untouched tail of a schedule
  /// before regenerating it under new interest/frequency/count terms.
  /// Unlike [closeOutRemaining] (which also writes off partially-paid
  /// installments as a permanent balance write-off), a partially-paid
  /// installment here is deliberately left alone — it already has a real
  /// payment recorded against it, and this operation replaces, not closes,
  /// the schedule.
  Future<List<Installment>> replaceUnpaid(List<Installment> installments) async {
    final untouched = installments.where((i) => i.amountPaid == 0 && !i.isSkipped).toList();
    for (final installment in untouched) {
      await softDelete(installment);
    }
    return untouched;
  }

  /// Installments due within the calendar week (Monday–Sunday) containing [now].
  List<Installment> thisWeek(List<Installment> all, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final start = today.startOfWeek;
    final end = today.endOfWeek;
    return all.where((i) => !i.dueDate.isBefore(start) && !i.dueDate.isAfter(end)).toList();
  }

  /// Installments due within the calendar month containing [now].
  List<Installment> thisMonth(List<Installment> all, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return all.where((i) => i.dueDate.isSameMonth(today)).toList();
  }

  /// Installments due within the calendar month immediately after [now]'s.
  List<Installment> nextMonth(List<Installment> all, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final next = DateTime(today.year, today.month + 1, 1);
    return all.where((i) => i.dueDate.isSameMonth(next)).toList();
  }

  /// Installments due strictly after [now]'s next calendar month (i.e. not
  /// this month, not next month).
  List<Installment> future(List<Installment> all, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final endOfNextMonth = DateTime(today.year, today.month + 2, 0, 23, 59, 59);
    return all.where((i) => i.dueDate.isAfter(endOfNextMonth)).toList();
  }

  /// Installments currently overdue as of [now] (defaults to today).
  /// Recomputes the same rule as [Installment.status] rather than reading
  /// that zero-arg getter directly, since [Installment.status] always uses
  /// the real `DateTime.now()` and can't be evaluated against an injected
  /// [now] (needed for deterministic tests).
  List<Installment> overdue(List<Installment> all, {DateTime? now}) {
    final today = (now ?? DateTime.now()).dateOnly;
    return all.where((i) {
      if (i.amountPaid >= i.amountDue || i.isSkipped || i.amountPaid > 0) return false;
      return i.dueDate.dateOnly.isBefore(today);
    }).toList();
  }

  /// Sum of remaining amounts across non-skipped installments.
  double remainingAmount(List<Installment> all) {
    return all
        .where((i) => i.status != InstallmentStatus.skipped)
        .fold(0.0, (total, i) => total + i.remainingAmount);
  }
}
