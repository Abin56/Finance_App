import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/person_timeline_entry.dart';

/// The history filters a person's timeline supports. Bills/EMI are omitted
/// (see [[ux_plain_language_rule]] context in the Task 2 plan — neither
/// feature has a person link in this codebase).
enum PersonTimelineFilter { all, lending, expenses, splitExpenses, payments, received, adjustments }

extension PersonTimelineFilterX on PersonTimelineFilter {
  String get label {
    switch (this) {
      case PersonTimelineFilter.all:
        return 'All';
      case PersonTimelineFilter.lending:
        return 'Lending';
      case PersonTimelineFilter.expenses:
        return 'This person will pay';
      case PersonTimelineFilter.splitExpenses:
        return 'Shared expenses';
      case PersonTimelineFilter.payments:
        return 'Payments';
      case PersonTimelineFilter.received:
        return 'Received';
      case PersonTimelineFilter.adjustments:
        return 'Corrections';
    }
  }

  /// Money repaid *by you* to someone you borrowed from.
  static const _paymentTitles = {'Money repaid'};

  /// Money coming back to you — either a lending repayment or a settled
  /// loan installment.
  static const _receivedTitles = {'Money received back', 'Loan payment received'};

  bool matches(PersonTimelineEntry entry) {
    switch (this) {
      case PersonTimelineFilter.all:
        return true;
      case PersonTimelineFilter.lending:
        return entry.category == PersonTimelineCategory.lending;
      case PersonTimelineFilter.expenses:
        return entry.category == PersonTimelineCategory.assignedExpense;
      case PersonTimelineFilter.splitExpenses:
        return entry.category == PersonTimelineCategory.splitExpense;
      case PersonTimelineFilter.payments:
        return _paymentTitles.contains(entry.title);
      case PersonTimelineFilter.received:
        return _receivedTitles.contains(entry.title);
      case PersonTimelineFilter.adjustments:
        return entry.category == PersonTimelineCategory.other;
    }
  }
}

/// Horizontal row of single-select filter chips for [PersonTimelineFilter].
class PersonTimelineFilterChips extends StatelessWidget {
  const PersonTimelineFilterChips({super.key, required this.selected, required this.onChanged});

  final PersonTimelineFilter selected;
  final ValueChanged<PersonTimelineFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in PersonTimelineFilter.values)
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
