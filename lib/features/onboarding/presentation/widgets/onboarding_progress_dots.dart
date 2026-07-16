import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// Progress indicator for the intro tour: one dot per page, the current one
/// stretched into a pill. Dots animate between states so a swipe reads as
/// continuous movement rather than a jump.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({
    super.key,
    required this.count,
    required this.currentIndex,
  });

  final int count;
  final int currentIndex;

  static const _dotSize = 8.0;
  static const _activeWidth = 26.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${currentIndex + 1} of $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < count; index++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: AppSizes.xs + 2),
              height: _dotSize,
              width: index == currentIndex ? _activeWidth : _dotSize,
              decoration: BoxDecoration(
                color: index == currentIndex
                    ? context.colors.primary
                    : context.colors.onSurface.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppSizes.radiusPill),
              ),
            ),
        ],
      ),
    );
  }
}
