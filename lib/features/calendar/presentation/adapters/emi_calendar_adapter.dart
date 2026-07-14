import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/router/app_routes.dart';
import '../../../emi/domain/emi.dart';
import '../../../emi/domain/emi_installment_display.dart';
import '../../domain/calendar_event.dart';

/// One [CalendarEvent] per due installment (not per EMI — an EMI recurs
/// monthly, so each unpaid, non-skipped installment is its own calendar
/// marker). [installmentsByScheduleId] is keyed by `Emi.scheduleId`.
List<CalendarEvent> emisToCalendarEvents(
  List<Emi> emis,
  Map<String, List<Installment>> installmentsByScheduleId,
) {
  final events = <CalendarEvent>[];
  for (final emi in emis) {
    final installments = installmentsByScheduleId[emi.scheduleId] ?? const [];
    for (final installment in installments) {
      if (installment.status == InstallmentStatus.paid || installment.isSkipped) continue;
      events.add(CalendarEvent(
        date: installment.dueDate.dateOnly,
        title: emi.name,
        subtitle: emiInstallmentStatusLabel(installment.status, installment.dueDate),
        color: installment.status.color,
        icon: installment.status.icon,
        routePath: '${AppRoutes.emis}/${emi.id}',
      ));
    }
  }
  return events;
}
