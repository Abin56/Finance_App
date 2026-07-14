import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';

/// A single takeaway about the period's spending/saving trend, e.g.
/// "You saved ₹X more compared to last month."
class ReportsInsightCard extends StatelessWidget {
  const ReportsInsightCard({super.key, required this.message, this.onTap});

  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.income, shape: BoxShape.circle),
            child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: AppSizes.iconMd),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Text(message, style: context.textTheme.bodyMedium)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
