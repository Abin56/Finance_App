import 'package:flutter/material.dart';

import '../../../../shared/widgets/states/empty_state.dart';

/// Thin SMS Inbox wrapper around the app's shared [EmptyState] widget —
/// reused, not reimplemented, per the feature's "no duplicated UI" rule.
class SmsEmptyState extends StatelessWidget {
  const SmsEmptyState({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.mark_email_read_outlined,
      title: 'No SMS found',
      subtitle: 'Nothing matches this filter yet. Pull down or refresh to scan for new financial SMS.',
      action: FilledButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Refresh'),
      ),
    );
  }
}
