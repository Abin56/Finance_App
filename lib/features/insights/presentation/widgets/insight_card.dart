import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../domain/insight.dart';

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

IconData _iconFor(InsightSeverity severity) {
  switch (severity) {
    case InsightSeverity.positive:
      return Icons.trending_up_rounded;
    case InsightSeverity.neutral:
      return Icons.info_outline_rounded;
    case InsightSeverity.warning:
      return Icons.trending_down_rounded;
  }
}

/// One [Insight] as a "Recent Insights" row — a tinted-icon-circle +
/// message layout (replacing the old single hardcoded predecessor this
/// generalizes), driven by [Insight.severity] rather than always being
/// green/positive.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight, this.onTap});

  final Insight insight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(insight.severity);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(_iconFor(insight.severity), color: Colors.white, size: AppSizes.iconMd),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Text(insight.message, style: context.textTheme.bodyMedium)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

/// A vertical list of [InsightCard]s, one per [insights] entry — renders
/// nothing when [insights] is empty rather than an empty section.
class InsightsList extends StatelessWidget {
  const InsightsList({super.key, required this.insights});

  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < insights.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSizes.sm),
          InsightCard(insight: insights[i]),
        ],
      ],
    );
  }
}
