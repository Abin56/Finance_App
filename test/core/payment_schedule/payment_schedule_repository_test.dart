import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PaymentScheduleRepository repository;

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    repository = PaymentScheduleRepository(collection);
  });

  group('PaymentScheduleRepository.createSchedule', () {
    test('rejects totalAmount <= 0', () async {
      await expectLater(
        repository.createSchedule(
          ownerType: OwnerType.loan,
          ownerId: 'loan-1',
          totalAmount: 0,
          scheduleType: ScheduleType.oneTime,
          firstDueDate: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects custom type without customIntervalDays', () async {
      await expectLater(
        repository.createSchedule(
          ownerType: OwnerType.loan,
          ownerId: 'loan-1',
          totalAmount: 100,
          scheduleType: ScheduleType.custom,
          firstDueDate: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('persists ownerType/ownerId correctly', () async {
      final schedule = await repository.createSchedule(
        ownerType: OwnerType.loan,
        ownerId: 'loan-42',
        totalAmount: 500,
        scheduleType: ScheduleType.monthly,
        firstDueDate: DateTime(2026, 1, 1),
        installmentCount: 5,
      );

      final fetched = await repository.getByKey(schedule.id);
      expect(fetched!.ownerType, OwnerType.loan);
      expect(fetched.ownerId, 'loan-42');
      expect(fetched.installmentCount, 5);
    });
  });

  group('PaymentScheduleRepository.editSchedule', () {
    test('records an audit entry per changed field', () async {
      final schedule = await repository.createSchedule(
        ownerType: OwnerType.loan,
        ownerId: 'loan-1',
        totalAmount: 100,
        scheduleType: ScheduleType.oneTime,
        firstDueDate: DateTime(2026, 1, 1),
        installmentCount: 1,
      );

      await repository.editSchedule(schedule, notes: 'Updated note');

      expect(schedule.editHistory.map((e) => e.field), contains('notes'));
    });
  });
}
