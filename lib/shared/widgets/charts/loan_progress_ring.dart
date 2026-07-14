import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/extensions/num_extensions.dart';

/// A circular completion indicator for a loan/EMI's paid-off progress —
/// same "used of a limit" concept as `ProgressBar`, just ring-shaped for the
/// EMI detail header and dashboard card per the premium loan UI spec.
class LoanProgressRing extends StatelessWidget {
  const LoanProgressRing({
    super.key,
    required this.progress,
    this.size = 96,
    this.strokeWidth = 8,
    this.color,
    this.centerLabel,
    this.centerSubLabel,
  });

  /// Raw ratio (not required to be pre-clamped — clamped internally via
  /// [NumX.clampedProgress]).
  final double progress;
  final double size;
  final double strokeWidth;
  final Color? color;
  final String? centerLabel;
  final String? centerSubLabel;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clampedProgress;
    final ringColor = color ?? context.colors.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: strokeWidth,
              color: context.colors.surfaceContainerHighest,
            ),
          ),
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: strokeWidth,
              color: ringColor,
              strokeCap: StrokeCap.round,
            ),
          ),
          if (centerLabel != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  centerLabel!,
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (centerSubLabel != null)
                  Text(
                    centerSubLabel!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
