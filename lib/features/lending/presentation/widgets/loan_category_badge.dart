import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../domain/loan_category.dart';

/// Small read-only pill spelling out a loan's category — "Personal" /
/// "Institution" — shown in the form's edit mode (category is immutable
/// after creation, see [LoanCategory]) and on the detail screen. Mirrors
/// [LoanDirectionBadge]'s shape, using [AppColors.purple] to stay visually
/// distinct from the given/taken direction badge's credit/debit coloring.
class LoanCategoryBadge extends StatelessWidget {
  const LoanCategoryBadge({super.key, required this.category});

  final LoanCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        category.formLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.purple,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
