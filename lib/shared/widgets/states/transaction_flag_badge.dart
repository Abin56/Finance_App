import 'package:flutter/material.dart';

import '../../../core/extensions/date_extensions.dart';

/// Small tinted pill flagging a transaction's excluded/reassigned-month
/// status — "Excluded" (grey) when [excludeFromCalculations], "Included in
/// {Month}" when [accountingMonth] is set and differs from [date]'s own
/// month. Renders nothing when neither applies, so callers can use it
/// unconditionally. Takes primitive fields rather than a [Transaction] so it
/// works equally for a `Transaction`-backed tile and a `HistoryEntry`
/// projection (built from several non-Transaction sources too). Mirrors
/// [ExpenseStatusPill]'s shape (`Container` + tinted background + `compact`
/// for dense rows) rather than inventing a second badge convention.
class TransactionFlagBadge extends StatelessWidget {
  const TransactionFlagBadge({
    super.key,
    required this.excludeFromCalculations,
    required this.date,
    this.accountingMonth,
    this.compact = false,
  });

  final bool excludeFromCalculations;
  final DateTime date;
  final DateTime? accountingMonth;

  /// Smaller padding/text for dense rows (e.g. inline in a list tile)
  /// instead of a standalone card.
  final bool compact;

  String? get _label {
    if (excludeFromCalculations) return 'Excluded';
    final accountingMonth = this.accountingMonth;
    if (accountingMonth != null && !accountingMonth.isSameMonth(date)) {
      return 'Included in ${accountingMonth.monthYear}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) return const SizedBox.shrink();

    const color = Colors.grey;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        label,
        style: (compact ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
