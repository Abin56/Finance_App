import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import 'onboarding_illustration.dart';

/// The content of a single onboarding page: artwork, headline, subtitle, and
/// an optional reassurance note. The action buttons deliberately live in the
/// host screen's fixed bottom bar instead of here, so they stay put while
/// pages slide underneath them.
///
/// The copy is laid out first and the artwork takes whatever height is left
/// over — never the reverse. Sizing the artwork as a fixed share of the page
/// instead pushed the SMS page's privacy note off the bottom of the screen
/// on every phone size, and because the note was still *built* (just parked
/// below the fold in a scroll view) nothing failed to warn about it. The
/// copy is the point of the page; the artwork is decoration, so the artwork
/// is what shrinks.
class OnboardingPageView extends StatelessWidget {
  const OnboardingPageView({
    super.key,
    required this.icon,
    required this.gradient,
    required this.headline,
    required this.subtitle,
    this.badges = const [],
    this.note,
  });

  final IconData icon;
  final List<Color> gradient;
  final String headline;
  final String subtitle;
  final List<OnboardingBadge> badges;

  /// Optional reassurance copy shown in a tinted card under the subtitle —
  /// used for the SMS page's privacy promise.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
      child: Column(
        children: [
          // Flexible, so the artwork gives up its height to the copy below
          // rather than pushing it off-screen. It can shrink to nothing on a
          // very short page or at a large system font size — losing the
          // decoration is always better than losing the words.
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxHeight
                    .clamp(0.0, constraints.maxWidth * 0.78)
                    .clamp(0.0, 260.0);
                return Center(
                  child: OnboardingIllustration(
                    icon: icon,
                    gradient: gradient,
                    size: size,
                    badges: badges,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                textAlign: TextAlign.center,
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.62),
                  height: 1.5,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: AppSizes.lg),
                _NoteCard(text: note!),
              ],
            ],
          )
              .animate()
              .fadeIn(duration: const Duration(milliseconds: 400))
              .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: AppSizes.lg),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      // Tint alone doesn't read as a card at these alphas — the same trap the
      // nav bar's indicator hit — so an outline carries the shape and the
      // fill only warms it. This note is the SMS page's whole reassurance;
      // it has to look like a deliberate promise, not stray body copy.
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: AppSizes.iconSm, color: context.colors.primary),
          const SizedBox(width: AppSizes.md),
          // Expanded so long privacy copy wraps inside the card instead of
          // overflowing the row at 360dp.
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
