import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/extensions/date_extensions.dart';

/// A month-only "◀ December 2026 ▶" stepper — no day picker exists in this
/// app because nothing else needs one; this is deliberately simpler than a
/// calendar widget since a month/year is all the caller needs. [value] and
/// [min]/[max] are always normalized to the first of a month by the caller.
class MonthYearStepper extends StatelessWidget {
  const MonthYearStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime min;
  final DateTime max;

  bool get _canGoBack => DateTime(value.year, value.month - 1).isAfter(min) ||
      DateTime(value.year, value.month - 1).isAtSameMomentAs(min);
  bool get _canGoForward => DateTime(value.year, value.month + 1).isBefore(max) ||
      DateTime(value.year, value.month + 1).isAtSameMomentAs(max);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous month',
          onPressed: _canGoBack ? () => onChanged(DateTime(value.year, value.month - 1)) : null,
        ),
        SizedBox(
          width: 140,
          child: Text(
            value.monthYear,
            textAlign: TextAlign.center,
            style: context.textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
          onPressed: _canGoForward ? () => onChanged(DateTime(value.year, value.month + 1)) : null,
        ),
      ],
    );
  }
}
