import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// The body of one wizard step: a tinted icon medallion, title, description,
/// an optional "Optional" tag, and a status line that flips to a green
/// "done" state once the step's underlying data exists.
///
/// Copy-first and scroll-safe, the same rule onboarding settled on — the
/// medallion sits in flexible space above the text and gives up its height
/// rather than pushing the description off a short screen or under a large
/// system font.
class SetupStepView extends StatelessWidget {
  const SetupStepView({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    this.optional = false,
    this.doneLabel,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final bool optional;

  /// When non-null the step is already satisfied — its data exists — and this
  /// reads back what's there (e.g. "1 account added"). Null means not yet done.
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: context.screenHeight * 0.42),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: AppSizes.xl),
            _Medallion(icon: icon, accent: accent, done: doneLabel != null),
            const SizedBox(height: AppSizes.xl),
            if (optional) ...[
              _OptionalTag(),
              const SizedBox(height: AppSizes.sm),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              description,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyLarge?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.62),
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            // Reserve the done-chip's row height at all times so the text
            // above it doesn't jump when a step flips to done.
            SizedBox(
              height: 28,
              child: doneLabel == null ? null : _DoneChip(label: doneLabel!),
            ),
            const SizedBox(height: AppSizes.md),
          ],
        )
            .animate()
            .fadeIn(duration: const Duration(milliseconds: 350))
            .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion({required this.icon, required this.accent, required this.done});

  final IconData icon;
  final Color accent;
  final bool done;

  @override
  Widget build(BuildContext context) {
    const size = 104.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: AppSizes.iconXl, color: accent),
          if (done)
            Positioned(
              right: size * 0.16,
              bottom: size * 0.16,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, size: 24, color: AppColors.success),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionalTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.xs),
      decoration: BoxDecoration(
        color: context.colors.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        'Optional',
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colors.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _DoneChip extends StatelessWidget {
  const _DoneChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.xs + 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: AppSizes.iconSm, color: AppColors.success),
          const SizedBox(width: AppSizes.xs + 2),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelLarge?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 250)).scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1, 1),
          curve: Curves.easeOutBack,
        );
  }
}
