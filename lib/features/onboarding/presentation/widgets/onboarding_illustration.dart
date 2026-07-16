import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// A floating accent badge orbiting an [OnboardingIllustration]'s hero tile.
///
/// [alignment] places it within the illustration's square box, so callers
/// position badges declaratively rather than juggling offsets.
class OnboardingBadge {
  const OnboardingBadge({
    required this.icon,
    required this.color,
    required this.alignment,
  });

  final IconData icon;
  final Color color;
  final Alignment alignment;
}

/// The artwork at the top of every onboarding page: a gradient hero tile
/// inside two soft halo rings, with small badges floating around it.
///
/// Drawn entirely with Flutter primitives rather than shipped as an image or
/// Lottie file — it re-tints itself for light/dark mode for free, stays
/// crisp at any size, and adds nothing to the APK. [size] is chosen by the
/// page layout from the height actually left over, which is what keeps the
/// artwork from squeezing the copy off-screen on short devices.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    super.key,
    required this.icon,
    required this.gradient,
    required this.size,
    this.badges = const [],
  });

  final IconData icon;
  final List<Color> gradient;
  final double size;
  final List<OnboardingBadge> badges;

  @override
  Widget build(BuildContext context) {
    final tile = size * 0.46;
    final accent = gradient.first;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _halo(accent, size, 0.06),
          _halo(accent, size * 0.76, 0.09),
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(tile * 0.3),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: AppSizes.blurMd,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, size: tile * 0.46, color: Colors.white),
          )
              .animate()
              .scale(
                duration: const Duration(milliseconds: 450),
                begin: const Offset(0.82, 0.82),
                end: const Offset(1, 1),
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: const Duration(milliseconds: 300)),
          for (final (index, badge) in badges.indexed)
            Align(
              alignment: badge.alignment,
              child: _Badge(badge: badge, size: size * 0.17)
                  .animate(delay: Duration(milliseconds: 220 + index * 110))
                  .fadeIn(duration: const Duration(milliseconds: 320))
                  .scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1), curve: Curves.easeOutBack)
                  .then()
                  // A slow, small bob keeps the artwork alive without the
                  // motion ever competing with the copy for attention.
                  .moveY(
                    begin: 0,
                    end: -6,
                    duration: const Duration(milliseconds: 1800),
                    curve: Curves.easeInOut,
                  )
                  .then()
                  .moveY(
                    begin: 0,
                    end: 6,
                    duration: const Duration(milliseconds: 1800),
                    curve: Curves.easeInOut,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _halo(Color color, double diameter, double alpha) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: color.withValues(alpha: alpha),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.badge, required this.size});

  final OnboardingBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: context.colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDarkMode ? 0.4 : 0.07),
            blurRadius: AppSizes.blurSm,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(badge.icon, size: size * 0.5, color: badge.color),
    );
  }
}
