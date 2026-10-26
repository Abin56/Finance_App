import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import 'dashboard_format.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/people/presentation/providers/people_providers.dart';
import '../../../../shared/widgets/animations/count_up_text.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/charts/mini_trend_chart.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import '../providers/dashboard_financial_summary_provider.dart';

/// Renders [DashboardWidgetType.netWorth] — the dashboard's hero card and its
/// only near-black surface (see [FlowFiCard.hero]: at most one per screen).
///
/// Every figure is read, never re-derived: the headline from
/// [dashboardFinancialSummaryProvider] (`netWorthWithLoansProvider`), the
/// Assets / Debt line from [netWorthCompositionProvider] (which reconciles to
/// the headline exactly), and the sparkline from [netWorthTrendProvider] —
/// real Net Worth per day, or an honest "unavailable" note when the last
/// week can't be replayed from records.
class NetWorthWidgetCard extends ConsumerWidget {
  const NetWorthWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = SectionLoad.of([
      ref.watch(accountsStreamProvider),
      ref.watch(creditCardsStreamProvider),
      ref.watch(loansStreamProvider),
      ref.watch(emisStreamProvider),
      ref.watch(peopleStreamProvider),
    ]);
    final hidden = ref.watch(netWorthHiddenProvider);
    final flowfi = context.flowfi;
    final textTheme = context.textTheme;

    return FlowFiCard.hero(
      accent: true,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.md,
        AppSizes.lg,
        AppSizes.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_rounded,
                size: AppSizes.iconSm,
                color: flowfi.onHeroSurfaceMuted,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  config.title,
                  style: textTheme.labelLarge?.copyWith(
                    color: flowfi.onHeroSurfaceMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () =>
                    ref.read(netWorthHiddenProvider.notifier).toggle(),
                tooltip: hidden ? 'Show net worth' : 'Hide net worth',
                icon: Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: AppSizes.iconSm + 2,
                  color: flowfi.onHeroSurfaceMuted,
                ),
              ),
            ],
          ),
          switch (load.status) {
            SectionLoadStatus.loading => const _HeroSkeleton(),
            SectionLoadStatus.error => Padding(
              padding: const EdgeInsets.only(top: AppSizes.sm),
              child: SectionErrorRow(
                message: "Couldn't load your net worth.",
                onRetry: () => invalidateDashboardSources(ref),
                onHeroSurface: true,
              ),
            ),
            SectionLoadStatus.ready => _HeroBody(hidden: hidden),
          },
        ],
      ),
    );
  }
}

class _HeroBody extends ConsumerWidget {
  const _HeroBody({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netWorth = ref.watch(dashboardFinancialSummaryProvider).netWorth;
    final composition = ref.watch(netWorthCompositionProvider);
    final trend = ref.watch(netWorthTrendProvider);
    final flowfi = context.flowfi;
    final textTheme = context.textTheme;
    final format = formatRupees;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: hidden
              ? Text(
                  '₹ ••••••',
                  style: textTheme.displayLarge?.copyWith(
                    color: flowfi.onHeroSurface,
                  ),
                )
              : CountUpText(
                  value: netWorth,
                  formatter: format,
                  style: textTheme.displayLarge?.copyWith(
                    color: flowfi.onHeroSurface,
                  ),
                ),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          'Everything you own, minus everything you owe',
          style: textTheme.bodySmall?.copyWith(
            color: flowfi.onHeroSurfaceMuted,
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          children: [
            Expanded(
              child: _HeroMetric(
                label: 'Assets',
                value: hidden ? '••••' : format(composition.assets),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: _HeroMetric(
                label: 'Debt',
                value: hidden ? '••••' : format(composition.debt),
                valueColor: composition.debt > 0 ? _debtOnHero : null,
                caption: hidden ? null : _debtCaption(composition),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        _TrendRow(trend: trend, hidden: hidden),
      ],
    );
  }

  /// A lighter expense red — the base token is too dark to read as a small
  /// figure on the near-black hero.
  static final Color _debtOnHero = Color.lerp(
    AppColors.expense,
    Colors.white,
    0.35,
  )!;

  String? _debtCaption(NetWorthComposition c) {
    final format = formatRupeesCompact;
    final parts = [
      if (c.loanDebt > 0) '${format(c.loanDebt)} loans/EMI',
      if (c.peopleDebt > 0) '${format(c.peopleDebt)} to people',
    ];
    return parts.isEmpty ? null : 'incl. ${parts.join(' · ')}';
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.caption,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final flowfi = context.flowfi;
    final textTheme = context.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: flowfi.heroSurfaceRaised,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: flowfi.onHeroSurfaceMuted,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: textTheme.titleSmall?.copyWith(
                color: valueColor ?? flowfi.onHeroSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              style: textTheme.labelSmall?.copyWith(
                color: flowfi.onHeroSurfaceMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.trend, required this.hidden});

  final NetWorthTrend trend;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final flowfi = context.flowfi;
    final caption = context.textTheme.labelSmall?.copyWith(
      color: flowfi.onHeroSurfaceMuted,
    );
    final values = trend.values;

    final Widget body;
    if (hidden) {
      body = const SizedBox.shrink();
    } else if (trend.status == NetWorthTrendStatus.loading) {
      body = Container(
        height: 36,
        decoration: BoxDecoration(
          color: flowfi.heroSurfaceRaised,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
      );
    } else if (values == null) {
      body = Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: AppSizes.iconSm,
            color: flowfi.onHeroSurfaceMuted,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              '7-day trend unavailable — recent loan, EMI, People or new-'
              'account activity can’t be replayed exactly.',
              style: caption,
            ),
          ),
        ],
      );
    } else if (trend.isFlat) {
      body = Text('No change in the last 7 days', style: caption);
    } else {
      final change = values.last - values.first;
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              label: 'Net worth over the last 7 days',
              child: MiniTrendChart(
                values: values,
                color: flowfi.heroAccent,
                height: 36,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${change >= 0 ? '+' : '−'}'
                    '${formatRupeesCompact(change.abs())}',
                    style: context.textTheme.labelLarge?.copyWith(
                      color: flowfi.onHeroSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text('Last 7 days', style: caption),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        const SizedBox(height: AppSizes.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push(AppRoutes.accounts),
            style: TextButton.styleFrom(
              foregroundColor: flowfi.onHeroSurface,
              backgroundColor: flowfi.heroSurfaceRaised,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
              textStyle: context.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Accounts'),
                Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final raised = context.flowfi.heroSurfaceRaised;
    Widget block(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: raised,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
    );
    return Semantics(
      label: 'Loading net worth',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(200, 40),
          const SizedBox(height: AppSizes.sm),
          block(220, 12),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(child: block(double.infinity, 48)),
              const SizedBox(width: AppSizes.sm),
              Expanded(child: block(double.infinity, 48)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          block(double.infinity, 36),
        ],
      ),
    );
  }
}
