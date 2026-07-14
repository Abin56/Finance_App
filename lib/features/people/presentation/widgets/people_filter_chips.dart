import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/person.dart';

/// The balance-direction filters the People list supports.
enum PeopleFilter { all, owesMe, iOwe, settled }

extension PeopleFilterX on PeopleFilter {
  String get label {
    switch (this) {
      case PeopleFilter.all:
        return 'All';
      case PeopleFilter.owesMe:
        return 'They Need to Pay Me';
      case PeopleFilter.iOwe:
        return 'I Need to Pay';
      case PeopleFilter.settled:
        return 'Nothing to Pay';
    }
  }

  bool matches(Person person) {
    switch (this) {
      case PeopleFilter.all:
        return true;
      case PeopleFilter.owesMe:
        return person.isCreditor;
      case PeopleFilter.iOwe:
        return person.isDebtor;
      case PeopleFilter.settled:
        return person.currentBalance == 0;
    }
  }
}

/// Horizontal row of single-select filter chips for [PeopleFilter].
class PeopleFilterChips extends StatelessWidget {
  const PeopleFilterChips({super.key, required this.selected, required this.onChanged});

  final PeopleFilter selected;
  final ValueChanged<PeopleFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in PeopleFilter.values)
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
