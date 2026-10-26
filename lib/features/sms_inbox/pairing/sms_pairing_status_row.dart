import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import '../data/captured_uid_resolver.dart';
import 'sms_pairing_providers.dart';
import 'sms_pairing_service.dart';

/// "FlowFi Web" row in the SMS Auto Sync card: whether this install is paired
/// with the signed-in account, and a confirmed Disconnect. The local flag only
/// describes what this phone last knew — the server decides what may upload.
class SmsPairingStatusRow extends ConsumerStatefulWidget {
  const SmsPairingStatusRow({
    super.key,
    this.uidResolver = defaultCapturedUidResolver,
  });

  final CapturedUidResolver uidResolver;

  @override
  ConsumerState<SmsPairingStatusRow> createState() =>
      _SmsPairingStatusRowState();
}

class _SmsPairingStatusRowState extends ConsumerState<SmsPairingStatusRow> {
  bool _busy = false;

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect from FlowFi Web?'),
        content: const Text(
          'This phone stops sending SMS candidates to your account on its next scan. '
          'Candidates already on the web stay there for review, and messages stay on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      await ref.read(smsPairingServiceProvider).disconnectThisDevice();
      message = 'Disconnected from FlowFi Web.';
    } on SmsPairingException catch (e) {
      message = e.failure.message;
    }
    ref.invalidate(smsPairedUidProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uidResolver();
    final pairedUid = ref.watch(smsPairedUidProvider).value;
    final paired = uid != null && pairedUid == uid;
    final textTheme = context.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text('FlowFi Web', style: textTheme.bodySmall)),
          Text(
            paired ? 'Paired' : 'Not paired',
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (paired) ...[
            const SizedBox(width: AppSizes.xs),
            TextButton(
              onPressed: _busy ? null : _disconnect,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Disconnect'),
            ),
          ],
        ],
      ),
    );
  }
}
