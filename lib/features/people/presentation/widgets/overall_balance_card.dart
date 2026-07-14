import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';

/// Net balance across every person — the sum of every "they owe you" minus
/// every "you owe them", so a positive total nets to "You are owed" and a
/// negative one to "You owe".
class OverallBalanceCard extends StatelessWidget {
  const OverallBalanceCard({super.key, required this.netBalance});

  final double netBalance;

  @override
  Widget build(BuildContext context) {
    final direction = MoneyDirectionX.forSignedBalance(netBalance) ?? MoneyDirection.completed;
    final statusLabel = netBalance == 0
        ? 'Nothing to Pay'
        : netBalance > 0
        ? 'They Need to Pay Me'
        : 'I Need to Pay';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall Balance',
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            CurrencyFormatter.instance.format(netBalance.abs()),
            style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: direction.color),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            statusLabel,
            style: context.textTheme.bodyMedium?.copyWith(color: direction.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
