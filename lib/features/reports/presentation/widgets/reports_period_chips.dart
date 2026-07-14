import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/reports_period.dart';

/// Single-select period chips ("This Month" / "Last Month" / "This Year"
/// [/ "Custom"]) shared by the Reports dashboard and category detail
/// screens — same visual pattern as [PersonTimelineFilterChips].
class ReportsPeriodChips extends StatelessWidget {
  const ReportsPeriodChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.periods = const [ReportsPeriod.thisMonth, ReportsPeriod.lastMonth, ReportsPeriod.thisYear],
  });

  final ReportsPeriod selected;
  final ValueChanged<ReportsPeriod> onChanged;
  final List<ReportsPeriod> periods;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < periods.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSizes.sm),
            ChoiceChip(
              label: Text(periods[i].label),
              selected: selected == periods[i],
              onSelected: (_) => onChanged(periods[i]),
            ),
          ],
        ],
      ),
    );
  }
}
