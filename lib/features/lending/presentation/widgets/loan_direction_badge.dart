import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/loan_direction.dart';

/// Small colored pill spelling out which way a loan flows — "You will
/// receive" / "You need to pay" — reused by [LoanTile], [LoanDetailScreen],
/// and the dashboard's Loans card.
class LoanDirectionBadge extends StatelessWidget {
  const LoanDirectionBadge({super.key, required this.direction});

  final LoanDirection direction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: direction.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        direction.badgeLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: direction.color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
