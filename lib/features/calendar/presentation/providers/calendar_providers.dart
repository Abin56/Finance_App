import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../domain/calendar_event.dart';
import '../adapters/bill_calendar_adapter.dart';
import '../adapters/emi_calendar_adapter.dart';

/// Every calendar event across features — Bills and EMI today, extensible
/// to future schedule-owning features without the screen needing to know
/// which feature produced which event.
final calendarEventsProvider = Provider<List<CalendarEvent>>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final billEvents = billsToCalendarEvents(bills);

  final emis = ref.watch(emisStreamProvider).value ?? const [];
  final installmentsByScheduleId = <String, List<Installment>>{
    for (final emi in emis) emi.scheduleId: ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [],
  };
  final emiEvents = emisToCalendarEvents(emis, installmentsByScheduleId);

  return [...billEvents, ...emiEvents];
});

/// Every event due on [date].
final calendarEventsForDateProvider = Provider.family<List<CalendarEvent>, DateTime>((ref, date) {
  final events = ref.watch(calendarEventsProvider);
  final target = date.dateOnly;
  return events.where((e) => e.date == target).toList();
});
