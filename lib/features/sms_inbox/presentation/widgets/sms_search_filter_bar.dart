import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
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
    final active = activeCount > 0;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.sm,
          AppSizes.lg,
          0,
        ),
        // One unified flat-outlined bar (search + filter merged, divided by
        // a hairline) instead of two separate shadowed/gradient elements —
        // reads as a single control rather than two competing surfaces.
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: active
                  ? AppClay.primaryAccent(context)
                  : context.colors.onSurface.withValues(alpha: 0.15),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  textInputAction: TextInputAction.search,
                  style: context.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search merchant, bank, amount…',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: AppSizes.iconMd,
                      color: context.colors.onSurface.withValues(alpha: 0.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: AppSizes.md),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (value) => ref.read(smsSearchQueryProvider.notifier).state = value,
                ),
              ),
              Container(width: 1, height: 24, color: context.colors.onSurface.withValues(alpha: 0.12)),
              _FilterButton(
                activeCount: activeCount,
                onPressed: () => SmsFilterSheet.show(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badges the active facet count so the user can tell the feed is filtered
/// even after scrolling the chips out of view. Sits flush inside the same
/// bordered bar as the search field rather than as its own floating button.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return InkWell(
      onTap: onPressed,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppSizes.radiusMd)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: AppSizes.iconMd,
              color: active ? AppClay.primaryAccent(context) : context.colors.onSurface.withValues(alpha: 0.6),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppClay.primaryAccent(context),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Text(
                  '$activeCount',
                  style: context.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
