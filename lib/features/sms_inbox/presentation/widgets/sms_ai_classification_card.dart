import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../providers/sms_inbox_providers.dart';
import 'sms_consent_sheets.dart';

/// "AI help for unclear SMS" switch in the SMS Inbox. Off by default; turning
/// it on requires confirming [SmsAiConsentDialog], turning it off takes effect
/// at once (the gate re-reads consent before every request).
class SmsAiClassificationCard extends ConsumerWidget {
  const SmsAiClassificationCard({super.key});

  static const double _radius = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(smsAiClassificationConsentProvider);
    final notifier = ref.read(smsAiClassificationConsentProvider.notifier);
    final muted = context.colors.onSurface.withValues(alpha: 0.65);

    Future<void> onChanged(bool value) async {
      if (!value) return notifier.withdraw();
      if (await SmsAiConsentDialog.show(context)) await notifier.grant();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSizes.sm,
        AppSizes.xs,
        AppSizes.xs,
        AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI help for unclear SMS',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'On. Unclear messages are sent, with long numbers '
                              'masked, to Anthropic for classification.'
                        : 'Off. No message text is sent for AI. FlowFi '
                              'still recognises SMS on this phone.',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            key: const ValueKey('sms-ai-consent-switch'),
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
