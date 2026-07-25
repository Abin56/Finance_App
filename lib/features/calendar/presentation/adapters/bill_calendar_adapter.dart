import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../bills/domain/bill.dart';
import '../../../bills/domain/bill_occurrence.dart';
import '../../../bills/domain/bill_status.dart';
import '../../domain/calendar_event.dart';

/// One [CalendarEvent] per bill, at its current occurrence's due date.
/// [occurrenceByBillId] is `currentOccurrenceByBillIdProvider` — a bill
/// with no materialized occurrence yet contributes no event.
List<CalendarEvent> billsToCalendarEvents(List<Bill> bills, Map<String, BillOccurrence> occurrenceByBillId) {
  final events = <CalendarEvent>[];
  for (final bill in bills) {
    final occurrence = occurrenceByBillId[bill.id];
    if (occurrence == null) continue;
    events.add(CalendarEvent(
      date: occurrence.dueDate.dateOnly,
      title: bill.name,
      subtitle: occurrence.status.label,
      color: occurrence.status.color,
      icon: occurrence.status.icon,
      routePath: '${AppRoutes.bills}/${bill.id}',
    ));
  }
  return events;
}
