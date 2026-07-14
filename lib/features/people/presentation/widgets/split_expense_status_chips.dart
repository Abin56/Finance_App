import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/person_timeline_entry.dart';

/// "All split expenses" requirement's Pending/Collected/History breakdown,
/// scoped to whatever's already selected by [PersonTimelineFilter] (usually
/// [PersonTimelineFilter.splitExpenses] or [PersonTimelineFilter.expenses]).
/// History means every entry regardless of status — same list as All, kept
/// as a separate option since "All" reads as "every split expense" while
/// "History" reads as "the full past record" in the spec's wording.
enum SplitExpenseStatusFilter { all, pending, collected, history }

extension SplitExpenseStatusFilterX on SplitExpenseStatusFilter {
  String get label {
    switch (this) {
      case SplitExpenseStatusFilter.all:
        return 'All';
      case SplitExpenseStatusFilter.pending:
        return 'Still to Pay';
      case SplitExpenseStatusFilter.collected:
        return 'Received';
      case SplitExpenseStatusFilter.history:
        return 'History';
    }
  }

  bool matches(PersonTimelineEntry entry) {
    switch (this) {
      case SplitExpenseStatusFilter.all:
      case SplitExpenseStatusFilter.history:
        return true;
      case SplitExpenseStatusFilter.pending:
        return entry.status == PersonTimelineStatus.pending ||
            entry.status == PersonTimelineStatus.partial ||
            entry.status == PersonTimelineStatus.overdue;
      case SplitExpenseStatusFilter.collected:
        return entry.status == PersonTimelineStatus.completed;
    }
  }
}

/// Horizontal row of single-select filter chips for [SplitExpenseStatusFilter]
/// — only meaningful once a split-expense-only [PersonTimelineFilter] is
/// active, so the caller shows this conditionally.
class SplitExpenseStatusChips extends StatelessWidget {
  const SplitExpenseStatusChips({super.key, required this.selected, required this.onChanged});

  final SplitExpenseStatusFilter selected;
  final ValueChanged<SplitExpenseStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in SplitExpenseStatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSizes.xs),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: selected == filter,
                onSelected: (_) => onChanged(filter),
              ),
            ),
        ],
      ),
    );
  }
}
