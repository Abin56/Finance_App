import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/filter/sms_card_matcher.dart';
import '../providers/sms_inbox_providers.dart';

/// The active filters, one removable chip each, plus Clear All — so the user
/// can always see why the feed is narrowed and undo one facet without
/// reopening the sheet.
///
/// Renders nothing when no filter is active, which is what lets the pinned
/// header shrink back to just the search field.
class SmsActiveFilterChips extends ConsumerWidget {
  const SmsActiveFilterChips({super.key});

  /// Kept in sync with the header delegate's extent maths in
  /// `SmsInboxScreen` — a sliver header must not claim more than it paints.
  static const double height = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final criteria = ref.watch(smsFilterCriteriaProvider);
    if (!criteria.hasActiveFilters) return const SizedBox.shrink();

    final cardLabels = {
      for (final option in ref.watch(smsCardFilterOptionsProvider)) option.id: option.label,
    };

    final chips = criteria.chips(
      cardLabel: (id) => cardLabels[id] ?? (id == SmsCardMatcher.unknownCardId ? 'Unknown card' : 'Card'),
      formatAmount: CurrencyFormatter.instance.format,
    );

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.sm),
        itemCount: chips.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSizes.xs),
        itemBuilder: (context, index) {
          if (index == chips.length) {
            return ActionChip(
              label: const Text('Clear All'),
              labelStyle: context.textTheme.labelSmall?.copyWith(color: context.colors.error),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
              onPressed: () => ref.read(smsFilterCriteriaProvider.notifier).state = criteria.cleared(),
            );
          }

          final chip = chips[index];
          return InputChip(
            label: Text(chip.label),
            labelStyle: context.textTheme.labelSmall,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
            onDeleted: () => ref.read(smsFilterCriteriaProvider.notifier).state = chip.removed,
          );
        },
      ),
    );
  }
}
