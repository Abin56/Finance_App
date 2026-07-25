import 'package:finance_app/core/router/app_routes.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/bill_status.dart';
import 'package:finance_app/features/calendar/presentation/adapters/bill_calendar_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill bill({String id = 'b1', String name = 'Electricity', DateTime? nextDueDate}) {
    return Bill(
      id: id,
      name: name,
      amount: 100,
      nextDueDate: nextDueDate ?? DateTime(2026, 3, 10),
      recurrence: BillRecurrence.monthly,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  BillOccurrence occurrenceFor(Bill b, {required DateTime dueDate, double amountPaid = 0}) {
    return BillOccurrence(
      id: 'occ-${b.id}',
      billId: b.id,
      dueDate: dueDate,
      amount: b.amount,
      amountPaid: amountPaid,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  group('billsToCalendarEvents', () {
    test('produces one CalendarEvent per bill at its current occurrence\'s due date', () {
      final b1 = bill(id: 'b1');
      final b2 = bill(id: 'b2', name: 'Internet');
      final occurrenceByBillId = {
        'b1': occurrenceFor(b1, dueDate: DateTime(2026, 3, 10)),
        'b2': occurrenceFor(b2, dueDate: DateTime(2026, 3, 15)),
      };

      final events = billsToCalendarEvents([b1, b2], occurrenceByBillId);

      expect(events, hasLength(2));
      expect(events[0].date, DateTime(2026, 3, 10));
      expect(events[1].date, DateTime(2026, 3, 15));
    });

    test('a bill with no materialized occurrence contributes no event', () {
      final b1 = bill(id: 'b1');

      final events = billsToCalendarEvents([b1], const {});

      expect(events, isEmpty);
    });

    test('routePath matches AppRoutes.bills/{id}', () {
      final b = bill(id: 'b1');
      final occurrenceByBillId = {'b1': occurrenceFor(b, dueDate: DateTime(2026, 3, 10))};

      final events = billsToCalendarEvents([b], occurrenceByBillId);

      expect(events.single.routePath, '${AppRoutes.bills}/b1');
    });

    test('subtitle/color reflect the occurrence\'s status', () {
      final b = bill(id: 'b1');
      final overdueOccurrence = occurrenceFor(b, dueDate: DateTime(2000, 1, 1));
      final occurrenceByBillId = {'b1': overdueOccurrence};

      final events = billsToCalendarEvents([b], occurrenceByBillId);

      expect(events.single.subtitle, overdueOccurrence.status.label);
      expect(events.single.color, overdueOccurrence.status.color);
    });
  });
}
