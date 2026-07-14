import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../bills/domain/bill.dart';
import '../../../bills/domain/bill_status.dart';
import '../../domain/calendar_event.dart';

/// One [CalendarEvent] per bill, at its current occurrence's due date.
List<CalendarEvent> billsToCalendarEvents(List<Bill> bills) {
  return bills
      .map((bill) => CalendarEvent(
            date: bill.dueDate.dateOnly,
            title: bill.name,
            subtitle: bill.status.label,
            color: bill.status.color,
            icon: bill.status.icon,
            routePath: '${AppRoutes.bills}/${bill.id}',
          ))
      .toList();
}
