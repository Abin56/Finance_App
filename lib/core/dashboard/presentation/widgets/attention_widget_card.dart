import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import '../providers/upcoming_due_provider.dart';
import 'dashboard_format.dart';
import 'upcoming_payments_widget_card.dart';

/// Renders [DashboardWidgetType.attention] — a slim strip, not a card: what
/// is overdue right now (one summed line) and what is due next, straight
/// from [dashboardAttentionProvider]. When nothing needs attention it
/// collapses to one calm "All caught up" line instead of an empty card.
/// Tapping a row opens the same detail the Upcoming Payments rows open.
class AttentionWidgetCard extends ConsumerWidget {
  const AttentionWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = SectionLoad.of([
      ref.watch(creditCardsStreamProvider),
      ref.watch(emisStreamProvider),
      ref.watch(loansStreamProvider),
      ref.watch(billsStreamProvider),
    ]);
    if (load.isLoading) {
      return const _StripShell(child: SectionSkeleton(rows: 1));
    }
    if (load.hasError) {
      return _StripShell(
        child: SectionErrorRow(
          message: "Couldn't check what's due.",
          onRetry: () => invalidateDashboardSources(ref),
        ),
      );
    }

    final attention = ref.watch(dashboardAttentionProvider);
    final overdue = attention.overdue;
    final next = attention.next;

    if (overdue.isEmpty && next == null) {
      return _StripShell(
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: AppSizes.iconSm + 2,
              color: AppColors.success,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'All caught up. ',
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: 'Nothing overdue or due this cycle.',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _StripShell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (overdue.isNotEmpty)
            _AttentionRow(
              icon: Icons.error_rounded,
              tone: AppColors.expense,
              eyebrow: overdue.length == 1
                  ? 'Overdue'
                  : '${overdue.length} payments overdue',
              title: overdue.length == 1
                  ? overdue.single.title
                  : 'Oldest: ${overdue.first.title}',
              detail: dueLabelFor(overdue.first.dueDate),
              amount: attention.overdueTotal,
              onTap: () => overdue.length == 1
                  ? openUpcomingDueItem(context, overdue.single)
                  : _OverdueListSheet.show(context, overdue),
            ),
          if (overdue.isNotEmpty && next != null)
            Divider(height: 1, color: context.colors.outline),
          if (next != null)
            _AttentionRow(
              icon: Icons.schedule_rounded,
              tone: AppColors.warning,
              eyebrow: 'Due next',
              title: next.title,
              detail: dueLabelFor(next.dueDate),
              amount: next.remaining,
              onTap: () => openUpcomingDueItem(context, next),
            ),
        ],
      ),
    );
  }
}

/// A flat bordered strip — deliberately lighter than a dashboard card so
/// the alert reads as part of the hero's context, not another section.
class _StripShell extends StatelessWidget {
  const _StripShell({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSizes.lg,
      vertical: AppSizes.md,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        side: BorderSide(color: context.colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.tone,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.amount,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String eyebrow;
  final String title;
  final String detail;
  final double amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Semantic edge marker — the color carries urgency, the eyebrow
            // text repeats it for anyone who can't rely on color.
            Container(width: 3, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  AppSizes.md,
                  AppSizes.sm,
                  AppSizes.md,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: AppSizes.iconMd, color: tone),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eyebrow.toUpperCase(),
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            title,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            detail,
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
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
                          formatRupees(amount),
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: AppSizes.iconSm,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every overdue item, oldest first — opened from the summed overdue row.
class _OverdueListSheet extends StatelessWidget {
  const _OverdueListSheet({required this.items});

  final List<UpcomingDueItem> items;

  static Future<void> show(BuildContext context, List<UpcomingDueItem> items) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OverdueListSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            0,
            AppSizes.lg,
            AppSizes.lg,
          ),
          children: [
            Text('Overdue', style: context.textTheme.titleMedium),
            const SizedBox(height: AppSizes.sm),
            for (final item in items) UpcomingDueRow(item: item),
          ],
        ),
      ),
    );
  }
}
