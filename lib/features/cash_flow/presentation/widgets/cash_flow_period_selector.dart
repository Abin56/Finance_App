import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../reports/domain/reports_period.dart';
import '../../domain/cash_flow_period.dart';
import '../providers/cash_flow_providers.dart';

/// The Cash Flow screen's date-range filter — a tappable pill showing the
/// current selection ("This Month", or "1 Sep 2026 – 30 Sep 2026" for a
/// custom range), opening a bottom sheet to change it. Selecting a preset
/// applies immediately; "Custom Range" opens `showDateRangePicker` before
/// applying. This is Feature 1 (the global Cash Flow filter) — it holds no
/// opinion about "My Expenses" or any other section; it only ever writes
/// [cashFlowDateRangeProvider].
class CashFlowPeriodSelector extends ConsumerWidget {
  const CashFlowPeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(cashFlowDateRangeProvider);
    final label = period.labelFor(DateTime.now());

    return ClayCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
      onTap: () => _openPicker(context, ref),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range_rounded, size: AppSizes.iconSm, color: context.colors.primary),
          const SizedBox(width: AppSizes.sm),
          Flexible(
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSizes.xs),
          Icon(Icons.expand_more_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.6)),
        ],
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<_PickerResult>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _PeriodPickerSheet(),
    );
    if (selected == null) return;

    if (selected.preset != CashFlowPreset.custom) {
      ref.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.preset(selected.preset);
      return;
    }

    if (!context.mounted) return;
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      initialDateRange: DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked == null) return;
    // `showDateRangePicker` returns both bounds at midnight (00:00:00) — the
    // end date must be pushed to the last instant of that day, or a
    // transaction later that same day would be wrongly excluded by an
    // inclusive-end comparison against a range that effectively stops at
    // its very first moment.
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
    ref.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
      DateRange(picked.start, end),
    );
  }
}

typedef _PickerResult = ({CashFlowPreset preset});

class _PeriodPickerSheet extends ConsumerWidget {
  const _PeriodPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(cashFlowDateRangeProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select period', style: context.textTheme.titleMedium),
            const SizedBox(height: AppSizes.md),
            for (final preset in CashFlowPreset.values) ...[
              _PresetTile(
                preset: preset,
                selected: current.preset == preset,
                onTap: () => Navigator.of(context).pop((preset: preset)),
              ),
              const SizedBox(height: AppSizes.xs),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.selected, required this.onTap});

  final CashFlowPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
      tileColor: selected ? context.colors.primary.withValues(alpha: 0.1) : null,
      leading: Icon(
        preset == CashFlowPreset.custom ? Icons.edit_calendar_outlined : Icons.calendar_today_outlined,
        color: selected ? context.colors.primary : context.colors.onSurface.withValues(alpha: 0.7),
      ),
      title: Text(
        preset.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? context.colors.primary : null,
        ),
      ),
      trailing: selected ? Icon(Icons.check_rounded, color: context.colors.primary) : null,
    );
  }
}
