import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/calendar/domain/calendar_event.dart';
import '../../../../features/calendar/presentation/providers/calendar_providers.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.calendar] — a lightweight "Upcoming Events"
/// summary reusing [calendarEventsProvider], the Calendar feature's own
/// event aggregation (Bills + EMI due dates today). Deliberately not a
/// second month-grid: the Calendar feature's own screen stays the single
/// place for full grid rendering/filtering — this card only lists the
/// nearest few events and links out to it.
class CalendarWidgetCard extends ConsumerWidget {
  const CalendarWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now().dateOnly;
    final events = ref.watch(calendarEventsProvider).where((e) => !e.date.isBefore(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final upcoming = events.take(5).toList();
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: AppSizes.sm),
              Flexible(
                child: GestureDetector(
                  onTap: () => context.push(AppRoutes.calendar),
                  child: Text(
                    'View Calendar ›',
                    style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (upcoming.isEmpty)
            Text('Nothing upcoming.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else
            for (final event in upcoming) _EventRow(event: event),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final colors = context.colors;
    final today = DateTime.now().dateOnly;
    final days = event.date.difference(today).inDays;
    final dateLabel = days == 0 ? 'Today' : days == 1 ? 'Tomorrow' : event.date.shortDate;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      onTap: () => context.push(event.routePath),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: event.color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(event.icon, size: AppSizes.iconSm, color: event.color),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    event.subtitle,
                    style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Text(dateLabel, style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
