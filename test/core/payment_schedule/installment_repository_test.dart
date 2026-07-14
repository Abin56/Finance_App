import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/precomputed_installment_amount.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PaymentScheduleRepository scheduleRepository;
  late InstallmentRepository installmentRepository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    scheduleRepository = PaymentScheduleRepository(scheduleCollection);

    final installmentCollection = firestore.collection('installments').withConverter<Installment>(
          fromFirestore: Installment.fromFirestore,
          toFirestore: (i, _) => i.toFirestore(),
        );
    installmentRepository = InstallmentRepository(installmentCollection);
  });

  Future<PaymentSchedule> createSchedule({
    required double totalAmount,
    required ScheduleType scheduleType,
    int? installmentCount,
    DateTime? firstDueDate,
  }) {
    return scheduleRepository.createSchedule(
      ownerType: OwnerType.loan,
      ownerId: 'loan-1',
      totalAmount: totalAmount,
      scheduleType: scheduleType,
      firstDueDate: firstDueDate ?? DateTime(2026, 1, 1),
      installmentCount: installmentCount,
    );
  }

  group('InstallmentRepository.generateInstallments — even split', () {
    test('oneTime creates exactly 1 installment with amountDue == totalAmount', () async {
      final schedule = await createSchedule(totalAmount: 500, scheduleType: ScheduleType.oneTime, installmentCount: 1);

      final installments = await installmentRepository.generateInstallments(schedule);

      expect(installments, hasLength(1));
      expect(installments.single.amountDue, 500);
    });

    test('monthly + fixed installmentCount splits evenly with correct due-date spacing', () async {
      final schedule = await createSchedule(
        totalAmount: 300,
        scheduleType: ScheduleType.monthly,
        installmentCount: 3,
        firstDueDate: DateTime(2026, 1, 5),
      );

      final installments = await installmentRepository.generateInstallments(schedule);

      expect(installments, hasLength(3));
      expect(installments.map((i) => i.amountDue), everyElement(100));
      expect(installments[0].dueDate, DateTime(2026, 1, 5));
      expect(installments[1].dueDate, DateTime(2026, 2, 5));
      expect(installments[2].dueDate, DateTime(2026, 3, 5));
    });

    test('odd amount: last installment absorbs the rounding remainder, total matches exactly', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.monthly, installmentCount: 3);

      final installments = await installmentRepository.generateInstallments(schedule);

      final total = installments.fold(0.0, (sum, i) => sum + i.amountDue);
      expect(total, closeTo(100, 0.01));
    });

    test('throws AppException when installmentCount is null', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: null);

      await expectLater(installmentRepository.generateInstallments(schedule), throwsA(isA<AppException>()));
    });
  });

  group('InstallmentRepository.generateInstallments — precomputed amounts', () {
    test('stamps exact amounts and principal/interest portions when provided', () async {
      final schedule = await createSchedule(totalAmount: 210, scheduleType: ScheduleType.monthly, installmentCount: 2);

      final installments = await installmentRepository.generateInstallments(
        schedule,
        precomputedAmounts: const [
          PrecomputedInstallmentAmount(amountDue: 105, principalPortion: 100, interestPortion: 5),
          PrecomputedInstallmentAmount(amountDue: 105, principalPortion: 100, interestPortion: 5),
        ],
      );

      expect(installments[0].amountDue, 105);
      expect(installments[0].principalPortion, 100);
      expect(installments[0].interestPortion, 5);
    });

    test('throws AppException when precomputedAmounts length mismatches installmentCount', () async {
      final schedule = await createSchedule(totalAmount: 210, scheduleType: ScheduleType.monthly, installmentCount: 2);

      await expectLater(
        installmentRepository.generateInstallments(
          schedule,
          precomputedAmounts: const [PrecomputedInstallmentAmount(amountDue: 210)],
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('InstallmentRepository.generateInstallments — dueDayOfMonth', () {
    test('installment #1 stays exactly on firstDueDate even when its day differs from dueDayOfMonth', () async {
      final schedule = await createSchedule(
        totalAmount: 400,
        scheduleType: ScheduleType.monthly,
        installmentCount: 4,
        firstDueDate: DateTime(2026, 2, 12),
      );

      final installments = await installmentRepository.generateInstallments(schedule, dueDayOfMonth: 5);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      expect(sorted[0].dueDate, DateTime(2026, 2, 12));
    });

    test('installments #2+ snap to the fixed dueDayOfMonth every month — matches the worked example', () async {
      // First EMI 12 Feb 2026, Monthly Due Date = 5.
      final schedule = await createSchedule(
        totalAmount: 400,
        scheduleType: ScheduleType.monthly,
        installmentCount: 4,
        firstDueDate: DateTime(2026, 2, 12),
      );

      final installments = await installmentRepository.generateInstallments(schedule, dueDayOfMonth: 5);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      expect(sorted[0].dueDate, DateTime(2026, 2, 12));
      expect(sorted[1].dueDate, DateTime(2026, 3, 5));
      expect(sorted[2].dueDate, DateTime(2026, 4, 5));
      expect(sorted[3].dueDate, DateTime(2026, 5, 5));
    });

    test('clamps to the last valid day in shorter months (e.g. due day 31 in February/30-day months)', () async {
      final schedule = await createSchedule(
        totalAmount: 400,
        scheduleType: ScheduleType.monthly,
        installmentCount: 4,
        firstDueDate: DateTime(2026, 1, 31),
      );

      final installments = await installmentRepository.generateInstallments(schedule, dueDayOfMonth: 31);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      expect(sorted[0].dueDate, DateTime(2026, 1, 31));
      expect(sorted[1].dueDate, DateTime(2026, 2, 28)); // 2026 is not a leap year
      expect(sorted[2].dueDate, DateTime(2026, 3, 31)); // reverts to 31 once the month allows it
      expect(sorted[3].dueDate, DateTime(2026, 4, 30)); // April only has 30 days
    });

    test('when firstDueDate.day already equals dueDayOfMonth, schedule is identical to the no-argument case', () async {
      final schedule = await createSchedule(
        totalAmount: 300,
        scheduleType: ScheduleType.monthly,
        installmentCount: 3,
        firstDueDate: DateTime(2026, 1, 5),
      );

      final withDueDay = await installmentRepository.generateInstallments(schedule, dueDayOfMonth: 5);
      final sorted = [...withDueDay]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      expect(sorted[0].dueDate, DateTime(2026, 1, 5));
      expect(sorted[1].dueDate, DateTime(2026, 2, 5));
      expect(sorted[2].dueDate, DateTime(2026, 3, 5));
    });

    test('null dueDayOfMonth behaves identically to before this parameter existed (regression guard)', () async {
      final schedule = await createSchedule(
        totalAmount: 300,
        scheduleType: ScheduleType.monthly,
        installmentCount: 3,
        firstDueDate: DateTime(2026, 1, 31),
      );

      final installments = await installmentRepository.generateInstallments(schedule);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      // Chains via ScheduleType.nextDueDate off the previous installment,
      // same as ScheduleType._addMonths' own end-of-month clamping.
      expect(sorted[0].dueDate, DateTime(2026, 1, 31));
      expect(sorted[1].dueDate, DateTime(2026, 2, 28));
      expect(sorted[2].dueDate, DateTime(2026, 3, 28)); // chained from Feb 28, not reset to 31
    });

    test('is ignored for non-monthly schedules', () async {
      final schedule = await createSchedule(
        totalAmount: 200,
        scheduleType: ScheduleType.weekly,
        installmentCount: 2,
        firstDueDate: DateTime(2026, 1, 5),
      );

      final installments = await installmentRepository.generateInstallments(schedule, dueDayOfMonth: 20);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      expect(sorted[1].dueDate, DateTime(2026, 1, 12)); // +7 days, dueDayOfMonth ignored
    });
  });

  group('InstallmentRepository.applyPayment', () {
    test('clamps amountPaid to amountDue and records an audit entry', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;

      await installmentRepository.applyPayment(installment, 150);

      expect(installment.amountPaid, 100);
      expect(installment.editHistory, isNotEmpty);
    });

    test('is a no-op for a zero delta', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;

      await installmentRepository.applyPayment(installment, 0);

      expect(installment.editHistory, isEmpty);
    });
  });

  group('InstallmentRepository.editInstallmentAmount', () {
    test('updates amountDue and records an audit entry', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;

      await installmentRepository.editInstallmentAmount(installment, 150);

      expect(installment.amountDue, 150);
      expect(installment.editHistory, isNotEmpty);
    });

    test('rejects an amount below what has already been paid', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;
      await installmentRepository.applyPayment(installment, 80);

      await expectLater(
        installmentRepository.editInstallmentAmount(installment, 50),
        throwsA(isA<AppException>()),
      );
      expect(installment.amountDue, 100);
    });
  });

  group('InstallmentRepository.editInstallmentDueDate', () {
    test('updates dueDate and records an audit entry', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;

      await installmentRepository.editInstallmentDueDate(installment, DateTime(2026, 2, 1));

      expect(installment.dueDate, DateTime(2026, 2, 1));
      expect(installment.editHistory, isNotEmpty);
    });

    test('is a no-op for the same due date', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;

      await installmentRepository.editInstallmentDueDate(installment, installment.dueDate);

      expect(installment.editHistory, isEmpty);
    });
  });

  group('Installment.status', () {
    test('upcoming for a future due date with amountPaid == 0', () {
      final installment = _installment(dueDate: DateTime.now().add(const Duration(days: 5)));
      expect(installment.status, InstallmentStatus.upcoming);
    });

    test('overdue for a past due date with amountPaid == 0', () {
      final installment = _installment(dueDate: DateTime.now().subtract(const Duration(days: 5)));
      expect(installment.status, InstallmentStatus.overdue);
    });

    test('partiallyPaid when 0 < amountPaid < amountDue regardless of due date', () {
      final installment = _installment(
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        amountPaid: 50,
      );
      expect(installment.status, InstallmentStatus.partiallyPaid);
    });

    test('paid when amountPaid >= amountDue', () {
      final installment = _installment(dueDate: DateTime.now(), amountPaid: 100);
      expect(installment.status, InstallmentStatus.paid);
    });

    test('skipped when isSkipped is true even if overdue', () {
      final installment = _installment(
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        isSkipped: true,
      );
      expect(installment.status, InstallmentStatus.skipped);
    });
  });

  group('InstallmentRepository.skipInstallment / unskipInstallment', () {
    test('toggle isSkipped and record audit entries', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;

      await installmentRepository.skipInstallment(installment);
      expect(installment.isSkipped, true);

      await installmentRepository.unskipInstallment(installment);
      expect(installment.isSkipped, false);
      expect(installment.editHistory, hasLength(2));
    });
  });

  group('InstallmentRepository.closeOutRemaining', () {
    test('soft-deletes not-fully-paid installments, leaves fully paid ones untouched', () async {
      final schedule = await createSchedule(totalAmount: 300, scheduleType: ScheduleType.monthly, installmentCount: 3);
      final installments = await installmentRepository.generateInstallments(schedule);
      await installmentRepository.applyPayment(installments[0], 100); // fully paid
      await installmentRepository.applyPayment(installments[1], 40); // partially paid

      final closed = await installmentRepository.closeOutRemaining(installments);

      expect(closed.map((i) => i.id), containsAll([installments[1].id, installments[2].id]));
      expect(closed.any((i) => i.id == installments[0].id), false);

      final remainingAfter = await installmentRepository.getAll();
      expect(remainingAfter.map((i) => i.id), [installments[0].id]);
    });

    test('is a no-op when every installment is already fully paid', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;
      await installmentRepository.applyPayment(installment, 100);

      final closed = await installmentRepository.closeOutRemaining([installment]);

      expect(closed, isEmpty);
      expect((await installmentRepository.getAll()), hasLength(1));
    });
  });

  group('InstallmentRepository.replaceUnpaid', () {
    test('soft-deletes only installments with zero payment, leaves paid and partially-paid alone', () async {
      final schedule = await createSchedule(totalAmount: 300, scheduleType: ScheduleType.monthly, installmentCount: 3);
      final installments = await installmentRepository.generateInstallments(schedule);
      await installmentRepository.applyPayment(installments[0], 100); // fully paid
      await installmentRepository.applyPayment(installments[1], 40); // partially paid

      final replaced = await installmentRepository.replaceUnpaid(installments);

      expect(replaced.map((i) => i.id), [installments[2].id]);
      final remainingAfter = await installmentRepository.getAll();
      expect(remainingAfter.map((i) => i.id), containsAll([installments[0].id, installments[1].id]));
      expect(remainingAfter.any((i) => i.id == installments[2].id), false);
    });

    test('does not touch a skipped installment', () async {
      final schedule = await createSchedule(totalAmount: 200, scheduleType: ScheduleType.monthly, installmentCount: 2);
      final installments = await installmentRepository.generateInstallments(schedule);
      await installmentRepository.skipInstallment(installments[0]);

      final replaced = await installmentRepository.replaceUnpaid(installments);

      expect(replaced.map((i) => i.id), [installments[1].id]);
      final remainingAfter = await installmentRepository.getAll();
      expect(remainingAfter.map((i) => i.id), [installments[0].id]);
    });

    test('is a no-op when every installment already carries a payment', () async {
      final schedule = await createSchedule(totalAmount: 100, scheduleType: ScheduleType.oneTime, installmentCount: 1);
      final installment = (await installmentRepository.generateInstallments(schedule)).single;
      await installmentRepository.applyPayment(installment, 50);

      final replaced = await installmentRepository.replaceUnpaid([installment]);

      expect(replaced, isEmpty);
      expect((await installmentRepository.getAll()), hasLength(1));
    });
  });

  group('InstallmentRepository query helpers', () {
    test('thisMonth/nextMonth/future/overdue correctly partition installments', () {
      final now = DateTime(2026, 3, 15);
      final all = [
        _installment(dueDate: DateTime(2026, 3, 20)), // this month, not yet due
        _installment(dueDate: DateTime(2026, 4, 10)), // next month
        _installment(dueDate: DateTime(2026, 6, 1)), // future
        _installment(dueDate: DateTime(2026, 2, 1)), // overdue
      ];

      expect(installmentRepository.thisMonth(all, now: now), hasLength(1));
      expect(installmentRepository.nextMonth(all, now: now), hasLength(1));
      expect(installmentRepository.future(all, now: now), hasLength(1));
      expect(installmentRepository.overdue(all, now: now), hasLength(1));
    });

    test('thisWeek returns installments due within the current Monday-Sunday week', () {
      final now = DateTime(2026, 3, 18); // Wednesday
      final all = [
        _installment(dueDate: DateTime(2026, 3, 16)), // Monday, same week
        _installment(dueDate: DateTime(2026, 3, 22)), // Sunday, same week
        _installment(dueDate: DateTime(2026, 3, 15)), // Sunday, prior week
        _installment(dueDate: DateTime(2026, 3, 23)), // Monday, next week
      ];

      expect(installmentRepository.thisWeek(all, now: now), hasLength(2));
    });

    test('remainingAmount sums correctly and excludes skipped installments', () {
      final all = [
        _installment(dueDate: DateTime.now(), amountDue: 100, amountPaid: 40),
        _installment(dueDate: DateTime.now(), amountDue: 50, isSkipped: true),
      ];

      expect(installmentRepository.remainingAmount(all), 60);
    });
  });
}

Installment _installment({
  required DateTime dueDate,
  double amountDue = 100,
  double amountPaid = 0,
  bool isSkipped = false,
}) {
  return Installment(
    id: 'i-${dueDate.millisecondsSinceEpoch}-${amountPaid}_$isSkipped',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: 1,
    dueDate: dueDate,
    amountDue: amountDue,
    amountPaid: amountPaid,
    isSkipped: isSkipped,
    createdAt: DateTime.now(),
  );
}
