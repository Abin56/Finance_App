import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import '../providers/upcoming_due_provider.dart';
import '../../../theme/clay_theme.dart';
import '../../../theme/clay_widgets.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.previousCycleCarryForward] — everything
/// still unpaid from before the current salary cycle started, filtered
/// straight out of [upcomingDueProvider] (`isCarriedOver == true`), the
/// same field the hero card's own "Carried Over From Previous Cycle"
/// section already keys off. No new aggregation: this is a dedicated,
/// always-visible surface for a subset of a list another card already
/// computes, since the PRD requires carry-forward to never be hidden
/// behind a Financial View instance the user might not have added.
class PreviousCycleWidgetCard extends ConsumerWidget {
  const PreviousCycleWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchorDay = switch (config.dateStrategy) {
      SalaryCycleToDate(:final anchorDay) => anchorDay,
      SalaryCycleFull(:final anchorDay) => anchorDay,
      _ => 17,
    };
    final cycle = SalaryCycleFull(anchorDay: anchorDay).resolve(DateTime.now());
    final items = ref.watch(upcomingDueProvider((start: cycle.start, end: cycle.end)));
    final carriedOver = items.where((i) => i.isCarriedOver).toList();
    final textTheme = context.textTheme;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    if (carriedOver.isEmpty) {
      return DashboardWidgetCard(
        backgroundColor: AppClay.success.withValues(alpha: 0.06),
        showHairline: false,
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: AppSizes.iconSm, color: AppClay.success),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                'Nothing carried over — previous cycle is fully settled.',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final total = carriedOver.fold(0.0, (sum, i) => sum + i.remaining);

    return DashboardWidgetCard(
      backgroundColor: AppClay.warning.withValues(alpha: 0.08),
      showHairline: false,
      onTap: () => context.go(AppRoutes.cashFlow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClayIconChip(
                icon: Icons.history_toggle_off_rounded,
                color: AppClay.warning,
                size: 28,
                iconSize: 15,
                glow: true,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  config.title,
                  style: textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    format.format(total),
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppClay.warning),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${carriedOver.length} ${carriedOver.length == 1 ? 'item' : 'items'} pending',
                    style: textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Carried forward from your previous pay period',
                  style: textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Flexible(
                child: Text(
                  'View Previous Cycle ›',
                  style: textTheme.labelSmall?.copyWith(color: AppClay.warning, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
