import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../providers/sms_inbox_providers.dart';
import '../screens/sms_inbox_screen.dart';

/// A small pill placed alongside `HistoryFilterChips` that *navigates* to
/// the SMS Inbox rather than filtering the History list in place — it
/// deliberately isn't a `HistoryFilter`/`ChoiceChip`, since an unconverted
/// SMS is local-only data that never becomes a `HistoryEntry`.
class SmsInboxEntryChip extends ConsumerWidget {
  const SmsInboxEntryChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(smsPendingCountProvider);

    return ActionChip(
      avatar: Badge(
        label: Text('$pendingCount'),
        isLabelVisible: pendingCount > 0,
        child: const Icon(Icons.mark_email_unread_outlined, size: AppSizes.iconSm),
      ),
      label: const Text('SMS Inbox'),
      onPressed: () => SmsInboxScreen.show(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
    );
  }
}
