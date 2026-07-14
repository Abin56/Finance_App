import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';

/// The status filters the EMI list supports — distinct from [EmiStatus]
/// itself since "All" and "Upcoming EMI" aren't derived statuses.
enum EmiListFilter { all, active, upcoming, overdue, defaulted, closed }

extension EmiListFilterX on EmiListFilter {
  String get label {
    switch (this) {
      case EmiListFilter.all:
        return 'All';
      case EmiListFilter.active:
        return 'Active';
      case EmiListFilter.upcoming:
        return 'Upcoming EMI';
      case EmiListFilter.overdue:
        return 'Missed Payment';
      case EmiListFilter.defaulted:
        return 'Defaulted';
      case EmiListFilter.closed:
        return 'Closed';
    }
  }
}

/// Horizontal row of single-select filter chips for [EmiListFilter].
class EmiStatusFilterChips extends StatelessWidget {
  const EmiStatusFilterChips({super.key, required this.selected, required this.onChanged});

  final EmiListFilter selected;
  final ValueChanged<EmiListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in EmiListFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSizes.xs),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: selected == filter,
                onSelected: (_) => onChanged(filter),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
              ),
            ),
        ],
      ),
    );
  }
}
