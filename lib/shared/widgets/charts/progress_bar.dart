import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/extensions/num_extensions.dart';

/// A labeled linear progress indicator for any "used of a limit" ratio —
/// budgets (spent/limit) and savings goals (saved/target) alike. Color
/// escalates from the theme primary to [AppColors.warning] at 80% and
/// [AppColors.error] at 100%+, so overspending/over-target is visible at a
/// glance without reading the numbers.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.progress, this.label, this.height = 8});

  /// Raw ratio (not required to be pre-clamped — this widget clamps via
  /// [NumX.clampedProgress] itself).
  final double progress;
  final String? label;
  final double height;

  Color _colorFor(BuildContext context, double ratio) {
    if (ratio >= 1) return AppColors.error;
    if (ratio >= 0.8) return AppColors.warning;
    return context.colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clampedProgress;
    final color = _colorFor(context, progress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: clamped),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) => LinearProgressIndicator(
              value: animatedValue,
              minHeight: height,
              backgroundColor: context.colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }
}
