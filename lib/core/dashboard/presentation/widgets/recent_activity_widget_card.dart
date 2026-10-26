import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/transactions/domain/history_entry.dart';
import '../../../../features/transactions/presentation/providers/history_providers.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import 'dashboard_format.dart';
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

  /// Same depth as Web's Recent transactions card.
  static const _rows = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = SectionLoad.of([ref.watch(transactionsStreamProvider)]);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            title: config.title,
            actionLabel: 'History',
            onAction: () => context.go(AppRoutes.transactions),
          ),
          const SizedBox(height: AppSizes.xs),
          DashboardSectionBody(
            load: load,
            errorMessage: "Couldn't load recent activity.",
            onRetry: () => invalidateDashboardSources(ref),
            builder: (context) {
              final entries = ref
                  .watch(historyEntriesProvider)
                  .take(_rows)
                  .toList();
              if (entries.isEmpty) {
                return const DashboardEmptyLine(
                  icon: Icons.receipt_long_outlined,
                  message: 'No activity yet — your recent entries show here.',
                );
              }
              return Column(
                children: [
                  for (final entry in entries) _CompactHistoryRow(entry: entry),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CompactHistoryRow extends StatelessWidget {
  const _CompactHistoryRow({required this.entry});

  final HistoryEntry entry;

  String get _when {
    final d = entry.date;
    if (d.isToday) return 'Today';
    if (d.isYesterday) return 'Yesterday';
    return d.shortDate;
  }

  @override
  Widget build(BuildContext context) {
    final color = entry.isCredit ? AppColors.income : AppColors.expense;
    final textTheme = context.textTheme;
    final colors = context.colors;
    final routePath = entry.routePath;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      onTap: routePath == null ? null : () => context.push(routePath),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            FlowFiIconChip(
              icon: entry.icon,
              color: color,
              size: 32,
              iconSize: AppSizes.iconSm,
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${entry.category.label} · $_when',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
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
                // Credits in green with "+"; debits stay in the primary text
                // color (as on Web) so a list of ordinary spends isn't a wall
                // of red.
                child: Text(
                  '${entry.isCredit ? '+' : '−'}${formatRupees(entry.amount)}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: entry.isCredit ? AppColors.income : colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
