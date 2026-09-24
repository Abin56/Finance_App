import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';

/// "Catch messages SMS misses" popup — the blocking dialog
/// `SmsInboxScreen._maybeShowNotificationAccessDialog` shows as soon as SMS
/// access is granted but notification access (the RCS-capture path) isn't.
/// Laid out as a plain, rounded confirmation card — eyebrow label, question,
/// an info row, then two equal-width side-by-side buttons — rather than the
/// app's flat hero-card language, per an explicit reference mockup for this
/// dialog specifically.
class NotificationAccessDialog extends StatelessWidget {
  const NotificationAccessDialog({super.key, required this.onEnable});

  final VoidCallback onEnable;

  /// [onEnable] fires after the dialog has already closed itself, so callers
  /// never need to pop it themselves.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onEnable,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => NotificationAccessDialog(
        onEnable: () {
          Navigator.of(dialogContext).pop();
          onEnable();
        },
      ),
    );
  }

  /// Local rounding for this one dialog's card/buttons — deliberately not
  /// [AppSizes.radiusLg] (pinned to 0 for the app's flat design language):
  /// the reference mockup this dialog was built from is explicitly
  /// soft-rounded, so it opts out rather than fighting that look.
  static const double _cardRadius = 20;
  static const double _buttonRadius = 14;
  static const double _buttonHeight = 42;
  static const double _iconBadgeSize = 44;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.md,
          AppSizes.lg,
          AppSizes.lg,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(_cardRadius),
          boxShadow: AppShadows.elevated(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'NOTIFICATION ACCESS',
              textAlign: TextAlign.center,
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.45),
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Divider(
              height: 1,
              color: context.colors.onSurface.withValues(alpha: 0.08),
            ),
            const SizedBox(height: AppSizes.md),
            FlowFiIconChip(
              icon: Icons.notifications_active_rounded,
              color: context.colors.primary,
              size: _iconBadgeSize,
              iconSize: AppSizes.iconMd,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              'Catch messages SMS misses',
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              'Some bank alerts (like SBI Credit Card RCS messages) arrive as RCS '
              'chat messages through Google Messages, which never show up in your '
              'device SMS inbox.',
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Container(
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: AppSizes.iconSm,
                    color: context.isDarkMode
                        ? AppColors.primaryDark
                        : context.colors.onSurface,
                  ),
                  const SizedBox(width: AppSizes.xs),
                  Expanded(
                    child: Text(
                      'Enable notification access so FlowFi can catch those too.',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.isDarkMode
                            ? AppColors.primaryDark
                            : context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: _buttonHeight,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.sm,
                        ),
                        side: BorderSide(
                          color: context.colors.onSurface.withValues(
                            alpha: 0.16,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_buttonRadius),
                        ),
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: context.colors.onSurface.withValues(alpha: 0.65),
                      ),
                      label: Text(
                        'Not now',
                        style: context.textTheme.labelLarge?.copyWith(
                          color: context.colors.onSurface.withValues(
                            alpha: 0.65,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: SizedBox(
                    height: _buttonHeight,
                    child: FilledButton.icon(
                      onPressed: onEnable,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_buttonRadius),
                        ),
                      ),
                      icon: const Icon(
                        Icons.notifications_active_rounded,
                        size: 16,
                      ),
                      label: const Text(
                        'Enable',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
