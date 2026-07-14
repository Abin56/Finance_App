import 'package:finance_app/core/router/app_routes.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/bill_status.dart';
import 'package:finance_app/features/calendar/presentation/adapters/bill_calendar_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('billsToCalendarEvents', () {
    test('produces one CalendarEvent per bill at its due date', () {
      final bills = [
        Bill(
          id: 'b1',
          name: 'Electricity',
          amount: 100,
          dueDate: DateTime(2026, 3, 10),
          recurrence: BillRecurrence.monthly,
          createdAt: DateTime(2026, 1, 1),
        ),
        Bill(
          id: 'b2',
          name: 'Internet',
          amount: 50,
          dueDate: DateTime(2026, 3, 15),
          recurrence: BillRecurrence.monthly,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final events = billsToCalendarEvents(bills);

      expect(events, hasLength(2));
      expect(events[0].date, DateTime(2026, 3, 10));
      expect(events[1].date, DateTime(2026, 3, 15));
    });

    test('routePath matches AppRoutes.bills/{id}', () {
      final bill = Bill(
        id: 'b1',
        name: 'Electricity',
        amount: 100,
        dueDate: DateTime(2026, 3, 10),
        recurrence: BillRecurrence.oneTime,
        createdAt: DateTime(2026, 1, 1),
      );

      final events = billsToCalendarEvents([bill]);

      expect(events.single.routePath, '${AppRoutes.bills}/b1');
    });

    test('subtitle/color reflect the bill status', () {
      final overdueBill = Bill(
        id: 'b1',
        name: 'Electricity',
        amount: 100,
        dueDate: DateTime(2000, 1, 1),
        recurrence: BillRecurrence.oneTime,
        createdAt: DateTime(2000, 1, 1),
      );

      final events = billsToCalendarEvents([overdueBill]);

      expect(events.single.subtitle, overdueBill.status.label);
      expect(events.single.color, overdueBill.status.color);
    });
  });
}
