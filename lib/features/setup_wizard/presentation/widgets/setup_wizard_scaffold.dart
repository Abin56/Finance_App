import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// Shared chrome for every setup-wizard step: a slim progress header, the
/// step body, and a fixed bottom action bar. Kept separate from onboarding's
/// scaffold on purpose — the wizard is a practical checklist, not the
/// inspirational tour, and the two are meant to look and feel distinct.
///
/// The body is handed the height left between header and actions and is
/// expected to fit within it (steps scroll internally if a large system font
/// pushes past that), which keeps the action bar pinned and jump-free as
/// steps change.
class SetupWizardScaffold extends StatelessWidget {
  const SetupWizardScaffold({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryBusy = false,
    this.secondaryLabel,
    this.onSecondary,
    this.onSkipAll,
    this.footerCaption,
  });

  /// Zero-based index of the visible step, for the "Step X of Y" readout and
  /// the progress bar fill.
  final int stepIndex;
  final int stepCount;

  final Widget body;

  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool primaryBusy;

  /// The decline-this-step action ("Skip" / "Later"). Null hides the slot —
  /// e.g. the final completion step, which has nothing to decline.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Dismisses the whole wizard (top-bar "Skip for now"). Null on the
  /// completion step, where finishing is the only way out.
  final VoidCallback? onSkipAll;

  /// Static reassurance text shown under the action bar in place of a
  /// secondary button — e.g. the completion step's "You can change these
  /// anytime in Settings." Ignored when [secondaryLabel] is set.
  final String? footerCaption;

  @override
  Widget build(BuildContext context) {
    final progress = (stepIndex + 1) / stepCount;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.md, 0),
              child: Row(
                children: [
                  // Expanded rather than a Spacer so an inflated counter (large
                  // system font on a 360dp screen) ellipsizes instead of
                  // shoving the skip button into an overflow.
                  Expanded(
                    child: Text(
                      'Step ${stepIndex + 1} of $stepCount',
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  if (onSkipAll != null)
                    TextButton(
                      onPressed: onSkipAll,
                      child: const Text('Skip for now'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl, vertical: AppSizes.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: context.colors.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
                child: body,
              ),
            ),
            _ActionBar(
              primaryLabel: primaryLabel,
              onPrimary: onPrimary,
              primaryBusy: primaryBusy,
              secondaryLabel: secondaryLabel,
              onSecondary: onSecondary,
              footerCaption: footerCaption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fixed bottom actions. The secondary slot holds its height even when empty
/// so the primary button never shifts between steps.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.primaryLabel,
    required this.onPrimary,
    required this.primaryBusy,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.footerCaption,
  });

  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool primaryBusy;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? footerCaption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.xl, AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: AppSizes.buttonHeight,
            child: FilledButton(
              onPressed: primaryBusy ? null : onPrimary,
              child: primaryBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(primaryLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          SizedBox(
            height: AppSizes.buttonHeight - AppSizes.sm,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: secondaryLabel != null
                  ? TextButton(
                      key: ValueKey(secondaryLabel),
                      onPressed: primaryBusy ? null : onSecondary,
                      child: Text(
                        secondaryLabel!,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: context.colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : footerCaption != null
                      ? Center(
                          key: ValueKey(footerCaption),
                          child: Text(
                            footerCaption!,
                            textAlign: TextAlign.center,
                            style: context.textTheme.labelMedium?.copyWith(
                              color: context.colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
