import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../providers/sms_inbox_providers.dart';
import 'sms_filter_sheet.dart';

/// Live search (merchant/bank/sender/reference/amount/body) beside the button
/// that opens [SmsFilterSheet] — distinct from `HistoryFilterChips`, which
/// filters already-converted history entries, not local SMS.
///
/// The old flat chip strip put every filter on one row, which forced the
/// facets to be mutually exclusive: picking "SBI" cleared "Pending". Moving
/// them into a sheet is what lets them combine.
class SmsSearchFilterBar extends ConsumerWidget {
  const SmsSearchFilterBar({super.key});

  /// The search row's height, kept in sync with the header delegate's extent.
  static const double height = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(smsFilterCriteriaProvider).activeCount;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.sm, AppSizes.sm, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                textInputAction: TextInputAction.search,
                style: context.textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search merchant, bank, amount…',
                  prefixIcon: const Icon(Icons.search_rounded, size: AppSizes.iconMd),
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSizes.md),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: context.colors.surfaceContainerHighest,
                ),
                onChanged: (value) => ref.read(smsSearchQueryProvider.notifier).state = value,
              ),
            ),
            _FilterButton(activeCount: activeCount, onPressed: () => SmsFilterSheet.show(context)),
          ],
        ),
      ),
    );
  }
}

/// Badges the active facet count so the user can tell the feed is filtered
/// even after scrolling the chips out of view.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Filter SMS',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: activeCount > 0,
        label: Text('$activeCount'),
        child: Icon(
          activeCount > 0 ? Icons.filter_list_rounded : Icons.filter_list_outlined,
          color: activeCount > 0 ? context.colors.primary : null,
        ),
      ),
    );
  }
}
