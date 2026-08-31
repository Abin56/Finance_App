import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';

/// The status filters the Loan list supports — distinct from [LoanStatus]
/// itself since "All" isn't a derived status, mirroring `EmiListFilter`.
enum LoanListFilter { all, active, overdue, closed }

extension LoanListFilterX on LoanListFilter {
  String get label {
    switch (this) {
      case LoanListFilter.all:
        return 'All';
      case LoanListFilter.active:
        return 'Active';
      case LoanListFilter.overdue:
        return 'Missed Payment';
      case LoanListFilter.closed:
        return 'Closed';
    }
  }
}

/// Which direction of loans to show — distinct from [LoanDirection] itself
/// since "All" isn't a real direction, mirroring [LoanListFilter].
enum LoanDirectionFilter { all, given, taken }

extension LoanDirectionFilterX on LoanDirectionFilter {
  String get label {
    switch (this) {
      case LoanDirectionFilter.all:
        return 'All';
      case LoanDirectionFilter.given:
        return 'I Gave';
      case LoanDirectionFilter.taken:
        return 'I Borrowed';
    }
  }
}

/// Horizontal row of single-select filter chips for [LoanDirectionFilter].
class LoanDirectionFilterChips extends StatelessWidget {
  const LoanDirectionFilterChips({super.key, required this.selected, required this.onChanged});

  final LoanDirectionFilter selected;
  final ValueChanged<LoanDirectionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in LoanDirectionFilter.values)
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

/// Which category of loans to show — distinct from [LoanCategory] itself
/// since "All" isn't a real category, mirroring [LoanDirectionFilter].
enum LoanCategoryFilter { all, personal, institutional }

extension LoanCategoryFilterX on LoanCategoryFilter {
  String get label {
    switch (this) {
      case LoanCategoryFilter.all:
        return 'All';
      case LoanCategoryFilter.personal:
        return 'Personal';
      case LoanCategoryFilter.institutional:
        return 'Institution';
    }
  }
}

/// Horizontal row of single-select filter chips for [LoanCategoryFilter].
class LoanCategoryFilterChips extends StatelessWidget {
  const LoanCategoryFilterChips({super.key, required this.selected, required this.onChanged});

  final LoanCategoryFilter selected;
  final ValueChanged<LoanCategoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in LoanCategoryFilter.values)
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

/// Horizontal row of single-select filter chips for [LoanListFilter].
class LoanStatusFilterChips extends StatelessWidget {
  const LoanStatusFilterChips({super.key, required this.selected, required this.onChanged});

  final LoanListFilter selected;
  final ValueChanged<LoanListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in LoanListFilter.values)
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
