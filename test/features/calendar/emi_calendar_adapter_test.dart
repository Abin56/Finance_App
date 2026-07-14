import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/router/app_routes.dart';
import 'package:finance_app/features/calendar/presentation/adapters/emi_calendar_adapter.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:flutter_test/flutter_test.dart';

Emi _emi({String id = 'emi-1', String scheduleId = 'schedule-1'}) {
  return Emi(
    id: id,
    name: 'Phone EMI',
    principalAmount: 1000,
    startDate: DateTime(2026, 1, 1),
    installmentFrequency: ScheduleType.monthly,
    installmentCount: 4,
    endDate: DateTime(2026, 4, 1),
    scheduleId: scheduleId,
    createdAt: DateTime(2026, 1, 1),
  );
}

Installment _installment({
  required String scheduleId,
  required int sequenceNumber,
  required DateTime dueDate,
  double amountPaid = 0,
  bool isSkipped = false,
}) {
  return Installment(
    id: 'i-$scheduleId-$sequenceNumber',
    scheduleId: scheduleId,
    ownerType: OwnerType.emi,
    ownerId: 'emi-1',
    sequenceNumber: sequenceNumber,
    dueDate: dueDate,
    amountDue: 250,
    amountPaid: amountPaid,
    isSkipped: isSkipped,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('emisToCalendarEvents', () {
    test('produces one event per non-paid, non-skipped installment', () {
      final emi = _emi();
      final installments = [
        _installment(scheduleId: 'schedule-1', sequenceNumber: 1, dueDate: DateTime(2026, 1, 1), amountPaid: 250),
        _installment(scheduleId: 'schedule-1', sequenceNumber: 2, dueDate: DateTime(2026, 2, 1)),
        _installment(scheduleId: 'schedule-1', sequenceNumber: 3, dueDate: DateTime(2026, 3, 1), isSkipped: true),
      ];

      final events = emisToCalendarEvents([emi], {'schedule-1': installments});

      expect(events, hasLength(1));
      expect(events.single.date, DateTime(2026, 2, 1));
    });

    test('multiple installments across different EMIs on the same date produce distinct events', () {
      final emiA = _emi(id: 'emi-a', scheduleId: 'schedule-a');
      final emiB = _emi(id: 'emi-b', scheduleId: 'schedule-b');
      final installmentsA = [_installment(scheduleId: 'schedule-a', sequenceNumber: 1, dueDate: DateTime(2026, 5, 1))];
      final installmentsB = [_installment(scheduleId: 'schedule-b', sequenceNumber: 1, dueDate: DateTime(2026, 5, 1))];

      final events = emisToCalendarEvents(
        [emiA, emiB],
        {'schedule-a': installmentsA, 'schedule-b': installmentsB},
      );

      expect(events, hasLength(2));
    });

    test('routePath matches AppRoutes.emis/{id}', () {
      final emi = _emi();
      final installments = [_installment(scheduleId: 'schedule-1', sequenceNumber: 1, dueDate: DateTime(2026, 2, 1))];

      final events = emisToCalendarEvents([emi], {'schedule-1': installments});

      expect(events.single.routePath, '${AppRoutes.emis}/emi-1');
    });
  });
}
