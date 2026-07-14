import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/calendar_event.dart';
import '../providers/calendar_providers.dart';

/// Unified monthly calendar with every feature's due dates marked (Bills,
/// EMI, and future schedule-owning features) — replaces the old
/// Bills-only calendar. Tapping a date shows that day's events below the
/// grid, each navigating to its own feature's detail screen.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now().dateOnly;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(calendarEventsProvider);
    final eventsForSelectedDate = ref.watch(calendarEventsForDateProvider(_selectedDate));

    final eventsByDate = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      eventsByDate.putIfAbsent(event.date, () => []).add(event);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Column(
        children: [
          TableCalendar<CalendarEvent>(
            firstDay: DateTime(2000),
            lastDay: DateTime(2100),
            focusedDay: _focusedMonth,
            selectedDayPredicate: (day) => day.dateOnly == _selectedDate,
            eventLoader: (day) => eventsByDate[day.dateOnly] ?? const [],
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDate = selected.dateOnly;
                _focusedMonth = focused;
              });
            },
            onPageChanged: (focused) => _focusedMonth = focused,
            calendarStyle: CalendarStyle(
              markerDecoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          ),
          const Divider(height: 1),
          Expanded(
            child: eventsForSelectedDate.isEmpty
                ? EmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'Nothing to pay',
                    subtitle: 'Nothing to pay on ${_selectedDate.fullDate}.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSizes.lg),
                    children: [
                      for (final event in eventsForSelectedDate)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSizes.sm),
                          child: _CalendarEventTile(event: event),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(event.icon, color: event.color),
        title: Text(event.title),
        subtitle: Text(event.subtitle, style: TextStyle(color: event.color)),
        onTap: () => context.push(event.routePath),
      ),
    );
  }
}
