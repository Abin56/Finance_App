import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
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

    // The People tab's one hero figure — stronger shadow than the person
    // rows below it, mirroring the Net Worth hero card's treatment.
    return ClayCard(
      isHero: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall Balance',
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 2),
          Text(
            CurrencyFormatter.instance.format(netBalance.abs()),
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: direction.color),
          ),
          const SizedBox(height: 2),
          Text(
            statusLabel,
            style: context.textTheme.bodySmall?.copyWith(color: direction.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
