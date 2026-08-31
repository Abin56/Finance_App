import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../features/transactions/domain/history_entry.dart';
import '../../../../features/transactions/presentation/providers/history_providers.dart';
import '../../domain/widget_configuration.dart';
import '../../../theme/clay_theme.dart';
import '../../../theme/clay_widgets.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.recentActivity] — a true cross-feature
/// activity feed (Transactions, Bills, Credit Cards, EMI, Loans, Split
/// Expenses), reusing [historyEntriesProvider] verbatim rather than
/// building a second merge: that provider already fans out over every one
/// of those features (see `HistoryBuilder`) and is already sorted
/// newest-first. This card only takes the top few and renders a compact
/// row per entry — no event loading, filtering, or amount/status
/// computation happens here.
class RecentActivityWidgetCard extends ConsumerWidget {
  const RecentActivityWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyEntriesProvider).take(3).toList();
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () => context.go(AppRoutes.transactions),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          if (entries.isEmpty)
            Text('No activity yet.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else
            for (final entry in entries) _CompactHistoryRow(entry: entry),
        ],
      ),
    );
  }
}

class _CompactHistoryRow extends StatelessWidget {
  const _CompactHistoryRow({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.isCredit ? AppClay.income : AppClay.expense;
    final sign = entry.isCredit ? '+' : '-';
    final textTheme = context.textTheme;
    final colors = context.colors;
    final routePath = entry.routePath;

    return InkWell(
      borderRadius: BorderRadius.circular(AppClay.radiusSm),
      onTap: routePath == null ? null : () => context.push(routePath),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            ClayIconChip(icon: entry.icon, color: color),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    entry.category.label,
                    style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '$sign${CurrencyFormatter.instance.formatCompact(entry.amount)}',
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
