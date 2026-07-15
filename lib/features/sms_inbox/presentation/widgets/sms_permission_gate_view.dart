import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/sms_availability.dart';
import '../providers/sms_inbox_providers.dart';

/// Full-bleed explanation + call-to-action shown in place of the SMS list
/// whenever [smsAvailabilityProvider] isn't `granted`. Copy matches the
/// feature spec's permission-flow wording exactly.
class SmsPermissionGateView extends ConsumerWidget {
  const SmsPermissionGateView({super.key, required this.availability});

  final SmsAvailability availability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, title, body, action) = switch (availability) {
      SmsAvailability.notRequestedYet => (
          Icons.mark_email_unread_outlined,
          'Read your financial SMS?',
          'FlowFi only reads financial SMS stored on your device to help you quickly add transactions. '
              'Nothing is added automatically.',
          _Action('Allow SMS access', () => ref.read(smsAvailabilityProvider.notifier).request()),
        ),
      SmsAvailability.denied => (
          Icons.sms_failed_outlined,
          'SMS access is disabled.',
          'FlowFi needs permission to read your SMS inbox so it can show financial messages here for you to review.',
          _Action('Grant Permission', () => ref.read(smsAvailabilityProvider.notifier).request()),
        ),
      SmsAvailability.permanentlyDenied => (
          Icons.sms_failed_outlined,
          'SMS access is disabled.',
          'Enable SMS access for FlowFi in your device Settings to use the SMS Inbox.',
          _Action('Grant Permission', () => ref.read(smsAvailabilityProvider.notifier).openSettings()),
        ),
      SmsAvailability.unsupportedPlatform => (
          Icons.phone_iphone_rounded,
          'Not available on this device',
          'Reading SMS isn\'t supported on this platform. You can still use every other FlowFi feature as normal.',
          null,
        ),
      SmsAvailability.granted => (Icons.check_circle_rounded, '', '', null),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: AppSizes.iconXl, color: context.colors.primary),
            ),
            const SizedBox(height: AppSizes.xl),
            Text(title, style: context.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSizes.sm),
            Text(
              body,
              style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSizes.xl),
              FilledButton(onPressed: action.onPressed, child: Text(action.label)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}
