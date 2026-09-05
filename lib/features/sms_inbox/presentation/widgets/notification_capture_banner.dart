import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/notification_access_availability.dart';
import '../providers/sms_inbox_providers.dart';

/// Dismissible-per-session banner shown above the SMS Inbox list when
/// notification access isn't granted. Unlike [SmsPermissionGateView], this
/// never blocks the inbox — device-SMS reading (the primary source) works
/// fine without it. Enabling it additionally catches bank alerts that never
/// reach the SMS content provider at all, e.g. RCS Business Messaging
/// through Google Messages — see `NotificationCaptureListenerService`.
class NotificationCaptureBanner extends ConsumerStatefulWidget {
  const NotificationCaptureBanner({super.key});

  @override
  ConsumerState<NotificationCaptureBanner> createState() =>
      _NotificationCaptureBannerState();
}

class _NotificationCaptureBannerState
    extends ConsumerState<NotificationCaptureBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final availability = ref
        .watch(notificationAccessAvailabilityProvider)
        .value;
    if (availability == null ||
        availability == NotificationAccessAvailability.granted ||
        availability == NotificationAccessAvailability.unsupportedPlatform) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_active_outlined,
            color: context.colors.primary,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catch messages SMS misses',
                  style: context.textTheme.labelLarge,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  'Some bank alerts arrive as RCS chat messages, which never show up in your SMS inbox. '
                  'Enable notification access to catch those too.',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => ref
                        .read(notificationAccessAvailabilityProvider.notifier)
                        .openSettings(),
                    child: const Text('Enable'),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: AppSizes.iconSm),
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
