import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../../../insights/domain/insight.dart';
import '../../../insights/presentation/providers/insight_generation_provider.dart';
import '../../domain/reports_period.dart';

Color _colorFor(InsightSeverity severity) {
  switch (severity) {
    case InsightSeverity.positive:
      return AppColors.success;
    case InsightSeverity.neutral:
      return AppColors.info;
    case InsightSeverity.warning:
      return AppColors.warning;
  }
}

/// Financial Health Indicators — [healthIndicatorsProvider]'s fixed
/// Good/Fair/Poor-style badge set (Savings Rate, Credit Utilization, Debt
/// Trend, Cash Flow Trend, Spending Trend), rendered as a badge grid. Every
/// indicator is produced by the shared Insights rule layer
/// (`insight_rules.dart`) from figures this screen already has — no
/// threshold or scoring logic lives here. [range]/[previousRange]/[period]
/// are the same values `ReportsScreen` already computes for its own
/// Overview/Insights sections, passed straight through rather than
/// re-derived.
class FinancialHealthSection extends ConsumerWidget {
  const FinancialHealthSection({super.key, required this.range, required this.previousRange, required this.period});

  final DateRange range;
  final DateRange previousRange;
  final ReportsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicators =
        ref.watch(healthIndicatorsProvider((range: range, previousRange: previousRange, period: period)));
    if (indicators.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Financial Health'),
        AppCard(
          child: Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: [for (final indicator in indicators) _IndicatorBadge(indicator: indicator)],
          ),
        ),
      ],
    );
  }
}

class _IndicatorBadge extends StatelessWidget {
  const _IndicatorBadge({required this.indicator});

  final Insight indicator;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(indicator.severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        indicator.message,
        style: context.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
