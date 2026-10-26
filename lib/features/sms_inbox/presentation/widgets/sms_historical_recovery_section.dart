import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../data/captured_uid_resolver.dart';
import '../providers/sms_inbox_providers.dart';
import '../sms_historical_recovery.dart';

/// "Link earlier messages" — the one-time historical ownership recovery
/// inside the SMS Auto Sync card. Shown only while there is something to do:
/// eligible unowned candidates, or a previous run that can be retried.
/// Binding always goes through an explicit confirmation dialog.
class SmsHistoricalRecoverySection extends ConsumerStatefulWidget {
  const SmsHistoricalRecoverySection({
    super.key,
    this.uidResolver = defaultCapturedUidResolver,
  });

  final CapturedUidResolver uidResolver;

  @override
  ConsumerState<SmsHistoricalRecoverySection> createState() =>
      _SmsHistoricalRecoverySectionState();
}

class _SmsHistoricalRecoverySectionState
    extends ConsumerState<SmsHistoricalRecoverySection> {
  bool _running = false;
  SmsHistoricalRecoveryResult? _last;

  @override
  Widget build(BuildContext context) {
    final uid = widget.uidResolver();
    if (uid == null) return const SizedBox.shrink();
    final items = ref.watch(smsInboxItemsProvider).value ?? const [];
    final candidates = ref.watch(transactionCandidatesProvider).value;
    if (candidates == null) return const SizedBox.shrink();

    final eligible = smsRecoveryEligibleIds(items, {
      for (final c in candidates) c.smsItemId,
    }).length;
    final canRetry = _last?.canRetry ?? false;
    if (eligible == 0 && _last == null) return const SizedBox.shrink();

    final textTheme = context.textTheme;
    final muted = context.colors.onSurface.withValues(alpha: 0.65);

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eligible > 0) ...[
            Text(
              'Earlier messages: $eligible',
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '$eligible review ${eligible == 1 ? 'candidate was' : 'candidates were'} '
              'captured before FlowFi recorded which account '
              '${eligible == 1 ? 'it belongs' : 'they belong'} to, so '
              '${eligible == 1 ? 'it is' : 'they are'} not in your web '
              'Transaction Inbox.',
              style: textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
            ),
          ],
          if (_last != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              child: Text(
                describeSmsRecoveryResult(_last!),
                key: const Key('sms-recovery-result'),
                style: textTheme.bodySmall?.copyWith(
                  color: _last!.didUpload ? null : context.colors.error,
                  height: 1.35,
                ),
              ),
            ),
          if (eligible > 0 || canRetry)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _running
                    ? null
                    : () => eligible > 0
                          ? _confirmAndRun(uid, eligible)
                          : _run(uid),
                child: Text(
                  _running
                      ? 'Working…'
                      : eligible > 0
                      ? 'Link to this account and upload'
                      : 'Retry upload',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRun(String uid, int eligible) async {
    String? email;
    try {
      email = FirebaseAuth.instance.currentUser?.email;
    } catch (_) {}

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link earlier messages?'),
        content: Text(
          '$eligible SMS review ${eligible == 1 ? 'candidate' : 'candidates'} '
          'on this phone are not linked to any FlowFi account. They will be '
          'linked to the account you are signed in with now'
          '${email == null ? '' : ' ($email)'} and uploaded to its '
          'Transaction Inbox for review.\n\n'
          '• Messages linked to another account are not changed.\n'
          '• Nothing is imported — no transactions are created.\n'
          '• Messages already imported or dismissed on the web stay hidden.\n'
          '• All SMS stay on this phone.\n\n'
          'Only continue if these messages are yours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Link and upload'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(uid);
  }

  Future<void> _run(String uid) async {
    setState(() => _running = true);
    SmsHistoricalRecoveryResult result;
    try {
      result = await ref.read(smsHistoricalRecoveryProvider).run(uid);
    } catch (_) {
      result = const SmsHistoricalRecoveryResult(
        outcome: SmsRecoveryOutcome.offline,
      );
    }
    await ref.read(smsInboxItemsProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _running = false;
      _last = result;
    });
  }
}
