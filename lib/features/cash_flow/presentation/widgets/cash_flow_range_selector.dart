import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../reports/domain/reports_period.dart';
import '../../domain/cash_flow_preset.dart';
import '../providers/cash_flow_providers.dart';

/// Feature 1 — the Cash Flow Center's global date-range filter. Selecting a
/// preset or custom range here updates [cashFlowSelectionProvider], which
/// every date-dependent section on the screen reads from (see
/// `cash_flow_providers.dart`'s doc comment on that provider for which
/// sections are, and aren't, scoped by it).
class CashFlowRangeSelector extends ConsumerWidget {
  const CashFlowRangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(cashFlowSelectionProvider);

    return FlowFiCard(
      onTap: () => _showPicker(context, ref),
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded, size: AppSizes.iconSm, color: context.colors.primary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              selection.label,
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.expand_more_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.6)),
        ],
      ),
    );
  }

  Future<void> _showPicker(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<CashFlowPreset>(
      context: context,
      builder: (sheetContext) => _PresetSheet(current: ref.read(cashFlowSelectionProvider).preset),
    );
    if (result == null || !context.mounted) return;

    if (result != CashFlowPreset.custom) {
      ref.read(cashFlowSelectionProvider.notifier).state = CashFlowSelection(
        preset: result,
        range: result.rangeFor(DateTime.now()),
      );
      return;
    }

    final current = ref.read(cashFlowSelectionProvider).range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: current.start, end: current.end),
    );
    if (picked == null || !context.mounted) return;

    ref.read(cashFlowSelectionProvider.notifier).state = CashFlowSelection(
      preset: CashFlowPreset.custom,
      range: DateRange(picked.start, picked.end.add(const Duration(hours: 23, minutes: 59, seconds: 59))),
    );
  }
}

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.current});

  final CashFlowPreset current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in CashFlowPreset.values)
            ListTile(
              title: Text(preset.label),
              trailing: preset == current ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(preset),
            ),
        ],
      ),
    );
  }
}
