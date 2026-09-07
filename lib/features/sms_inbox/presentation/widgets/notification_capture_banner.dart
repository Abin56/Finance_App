import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../domain/battery_optimization_availability.dart';
import '../../domain/notification_access_availability.dart';
import '../providers/sms_inbox_providers.dart';

/// Dismissible-per-session banner shown above the SMS Inbox list whenever RCS
/// capture isn't actually going to work yet. Unlike [SmsPermissionGateView],
/// this never blocks the inbox — device-SMS reading (the primary source)
/// works fine without either step below.
///
/// Two independent steps, shown one at a time in the order they actually
/// matter:
///  1. Notification access itself (see `NotificationAccessService`) — no
///     point asking about battery behavior before this is even granted.
///  2. Battery-optimization exemption (see `BatteryOptimizationService`) —
///     an OEM background-freezing policy (Samsung's "Optimised" battery mode,
///     say) can silently stop `NotificationCaptureListenerService`'s callback
///     from ever running even once access is granted, so this is checked and
///     surfaced as its own follow-up rather than assumed.
class NotificationCaptureBanner extends ConsumerStatefulWidget {
  const NotificationCaptureBanner({super.key});

  @override
  ConsumerState<NotificationCaptureBanner> createState() =>
      _NotificationCaptureBannerState();
}

class _NotificationCaptureBannerState
    extends ConsumerState<NotificationCaptureBanner> {
  bool _dismissed = false;

  /// Matches [NotificationAccessDialog]'s soft-rounded look — this banner and
  /// that popup surface the same two RCS-capture follow-up steps, so they're
  /// deliberately styled as a matching pair rather than the app's flat
  /// (zero-radius) default.
  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final notificationAccess = ref
        .watch(notificationAccessAvailabilityProvider)
        .value;
    final batteryOptimization = ref
        .watch(batteryOptimizationAvailabilityProvider)
        .value;

    final _BannerContent? content = switch (notificationAccess) {
      null || NotificationAccessAvailability.unsupportedPlatform => null,
      NotificationAccessAvailability.granted => switch (batteryOptimization) {
        null ||
        BatteryOptimizationAvailability.unrestricted ||
        BatteryOptimizationAvailability.unsupportedPlatform => null,
        BatteryOptimizationAvailability.restricted => _BannerContent(
          title: 'Bank alerts may be missed',
          body:
              'Your device may pause FlowFi in the background, which can stop it from '
              'catching RCS bank alerts even with notification access on. Allow FlowFi '
              'to run unrestricted to make sure they always come through.',
          actionLabel: 'Allow',
          onAction: () => ref
              .read(batteryOptimizationAvailabilityProvider.notifier)
              .requestUnrestricted(),
        ),
      },
      NotificationAccessAvailability.denied ||
      NotificationAccessAvailability.notRequestedYet => _BannerContent(
        title: 'Catch messages SMS misses',
        body:
            'Some bank alerts arrive as RCS chat messages, which never show up in your '
            'SMS inbox. Enable notification access to catch those too.',
        actionLabel: 'Enable',
        onAction: () => ref
            .read(notificationAccessAvailabilityProvider.notifier)
            .openSettings(),
      ),
    };

    if (content == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlowFiIconChip(
            icon: Icons.notifications_active_rounded,
            color: context.colors.primary,
            size: 32,
            iconSize: 16,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSizes.xs / 2),
                Text(
                  content.body,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.65),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IntrinsicWidth(
                    child: SizedBox(
                      height: 28,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.primary,
                          borderRadius: BorderRadius.circular(_radius - 4),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(_radius - 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(_radius - 4),
                            onTap: content.onAction,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSizes.sm,
                              ),
                              child: Center(
                                child: Text(
                                  content.actionLabel,
                                  style: context.textTheme.labelSmall?.copyWith(
                                    color: context.colors.onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _dismissed = true),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: context.colors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerContent {
  const _BannerContent({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
}
