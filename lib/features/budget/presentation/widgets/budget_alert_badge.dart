import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../domain/budget_insight.dart';

/// Small colored dot + label reflecting a [BudgetInsight]'s discrete
/// [BudgetAlertLevel] — amber from 75%, red from 100%. Renders nothing
/// below 75% so budgets well within limit stay visually quiet.
class BudgetAlertBadge extends StatelessWidget {
  const BudgetAlertBadge({super.key, required this.level});

  final BudgetAlertLevel level;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (level) {
      BudgetAlertLevel.none || BudgetAlertLevel.at50 => (null, null),
      BudgetAlertLevel.at75 => (AppColors.warning, '75% used'),
      BudgetAlertLevel.at90 => (AppColors.warning, '90% used'),
      BudgetAlertLevel.at100 => (AppColors.error, 'Budget reached'),
      BudgetAlertLevel.over => (AppColors.error, 'Over budget'),
    };

    if (color == null || label == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: AppSizes.xs),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
