import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../providers/sms_inbox_providers.dart';

/// Prominent disclosure shown before Android's SMS permission prompt, from
/// every place that asks for it (onboarding, setup wizard, SMS Inbox).
///
/// Every line here must stay true to the code: candidate documents carry
/// parsed fields only (see `SmsTransactionCandidateCloud.toFirestore`), and
/// masked message text leaves the phone only through
/// `ConsentGatedFinancialEventAiProvider`, i.e. only after AI consent.
/// Update `/privacy` on FlowFi Web together with this text.
class SmsAccessConsentSheet extends StatelessWidget {
  const SmsAccessConsentSheet({super.key});

  /// True only when the user tapped Continue.
  static Future<bool> show(BuildContext context) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const SmsAccessConsentSheet(),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return _ConsentLayout(
      eyebrow: 'SMS ACCESS',
      icon: Icons.mark_email_unread_rounded,
      title: 'How FlowFi uses your SMS',
      points: const [
        (
          Icons.phone_android_rounded,
          'Reads SMS on this phone',
          'FlowFi reads your SMS inbox here and looks for bank and payment '
              'alerts. It never sends SMS.',
        ),
        (
          Icons.memory_rounded,
          'Recognises transactions on the phone',
          'Amount, merchant and date are worked out on this phone.',
        ),
        (
          Icons.cloud_upload_outlined,
          'Saves transaction details to your account',
          'Amount, merchant, bank, last 4 digits, reference number and date are '
              'saved to your FlowFi account so you can review them here and on '
              'FlowFi Web. The message text itself is not included.',
        ),
        (
          Icons.fact_check_outlined,
          'Nothing is recorded automatically',
          'Each one waits for you to import or dismiss it.',
        ),
        (
          Icons.sync_rounded,
          'Auto Sync is a separate choice',
          'FlowFi checks new SMS in the background only if you turn on Auto '
              'Sync.',
        ),
        (
          Icons.auto_awesome_outlined,
          'AI help stays off unless you turn it on',
          'If you turn it on, messages FlowFi can\'t read confidently are sent, '
              'with long numbers masked and the bank name, to Anthropic for '
              'classification.',
        ),
      ],
      declineLabel: 'Not now',
      acceptLabel: 'Continue',
    );
  }
}

/// Opt-in for cloud AI classification. Shown each time the switch is turned
/// on; withdrawing needs no dialog.
class SmsAiConsentDialog extends StatelessWidget {
  const SmsAiConsentDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const SmsAiConsentDialog(),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return const _ConsentLayout(
      eyebrow: 'AI CLASSIFICATION',
      icon: Icons.auto_awesome_rounded,
      title: 'Let AI help with unclear SMS?',
      points: [
        (
          Icons.send_outlined,
          'What is sent',
          'Only for messages FlowFi can\'t read confidently: the message text '
              'with every run of 5 or more digits cut to its last 4 (amounts '
              'are kept), the bank name, and what FlowFi already found.',
        ),
        (
          Icons.business_outlined,
          'Who processes it',
          'FlowFi\'s server passes it to Anthropic, an external AI provider, '
              'and uses the answer only to suggest the type, merchant and '
              'category.',
        ),
        (
          Icons.fact_check_outlined,
          'You still decide',
          'AI suggestions are never recorded as transactions on their own.',
        ),
        (
          Icons.toggle_off_outlined,
          'Turn it off any time',
          'With AI off, FlowFi still reads and recognises SMS on this phone.',
        ),
      ],
      declineLabel: 'Keep off',
      acceptLabel: 'Turn on AI',
    );
  }
}

/// Shows [SmsAccessConsentSheet], then — only if accepted — Android's own
/// permission prompt. Returns whether the prompt was reached.
Future<bool> requestSmsAccessWithConsent(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await SmsAccessConsentSheet.show(context)) return false;
  await ref.read(smsAvailabilityProvider.notifier).request();
  return true;
}

class _ConsentLayout extends StatelessWidget {
  const _ConsentLayout({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.points,
    required this.declineLabel,
    required this.acceptLabel,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final List<(IconData, String, String)> points;
  final String declineLabel;
  final String acceptLabel;

  static const double _buttonRadius = 14;
  static const double _buttonHeight = 46;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.onSurface.withValues(alpha: 0.62);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        0,
        AppSizes.lg,
        AppSizes.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            textAlign: TextAlign.center,
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.45),
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Center(
            child: FlowFiIconChip(
              icon: icon,
              color: context.colors.primary,
              size: 44,
              iconSize: AppSizes.iconMd,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          for (final (pointIcon, heading, body) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(pointIcon, size: AppSizes.iconSm + 2, color: muted),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heading,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _buttonHeight,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_buttonRadius),
                      ),
                    ),
                    child: Text(declineLabel),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: SizedBox(
                  height: _buttonHeight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_buttonRadius),
                      ),
                    ),
                    child: Text(
                      acceptLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
