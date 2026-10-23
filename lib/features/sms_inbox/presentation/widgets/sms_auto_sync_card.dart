import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/notification_access_availability.dart';
import '../../domain/sms_import_status.dart';
import '../providers/sms_auto_sync_providers.dart';
import '../providers/sms_inbox_providers.dart';

/// Compact "SMS Auto Sync" status/settings section for the SMS Inbox.
///
/// Honest about limits: capture depends on Android keeping the permissions
/// granted and the app not force-stopped, and RCS capture is best-effort
/// (it relies on Google Messages showing a notification). Hidden entirely on
/// builds without the native half (e.g. the `play` flavor).
class SmsAutoSyncCard extends ConsumerWidget {
  const SmsAutoSyncCard({super.key});

  static const double _radius = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(smsAutoSyncProvider).value;
    if (status == null || !status.supported) return const SizedBox.shrink();

    final notificationAccess = ref
        .watch(notificationAccessAvailabilityProvider)
        .value;
    final pendingReview = (ref.watch(smsInboxItemsProvider).value ?? const [])
        .where(
          (i) =>
              i.status == SmsImportStatus.pending &&
              !i.isDuplicate &&
              i.parsed != null,
        )
        .length;
    final notifier = ref.read(smsAutoSyncProvider.notifier);
    final textTheme = context.textTheme;
    final muted = context.colors.onSurface.withValues(alpha: 0.65);

    final rows = <(String, String)>[
      (
        'SMS permission',
        status.receiveSmsGranted && status.readSmsGranted
            ? 'Granted'
            : 'Not granted',
      ),
      (
        'RCS notification access',
        notificationAccess == NotificationAccessAvailability.granted
            ? 'On (best-effort)'
            : 'Off',
      ),
      (
        'Last background scan',
        status.lastSuccessAt == null
            ? 'Never'
            : DateFormat('d MMM, h:mm a').format(status.lastSuccessAt!),
      ),
      ('Waiting to be scanned', '${status.pendingSignals}'),
      ('Awaiting your review', '$pendingReview'),
    ];

    final errorText = status.permissionsRevoked
        ? 'Android removed SMS permission, so Auto Sync is paused. '
              'Turn it off and on again to re-grant it.'
        : status.errorLabel == null
        ? null
        : status.retryCount > 0
        ? '${status.errorLabel} (attempt ${status.retryCount})'
        : status.errorLabel;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SMS Auto Sync',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: status.enabled,
                onChanged: (on) async {
                  if (!on) {
                    await notifier.disable();
                    return;
                  }
                  final enabled = await notifier.enable();
                  if (!enabled && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Auto Sync needs SMS permission. Allow it in the '
                          'system prompt or in Settings > Apps > FlowFi.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          Text(
            'Looks for new bank alerts in the background and stores them on '
            'this device for review. Message text is never uploaded from '
            'here. Android can still pause capture (permissions removed, app '
            'force-stopped, battery limits).',
            style: textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
          ),
          const SizedBox(height: AppSizes.xs),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: textTheme.bodySmall)),
                  Text(
                    value,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              child: Text(
                errorText,
                style: textTheme.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          if (status.isEffective)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: notifier.scanNow,
                child: const Text('Scan now'),
              ),
            ),
        ],
      ),
    );
  }
}
