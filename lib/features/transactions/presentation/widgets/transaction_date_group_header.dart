import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';

/// Section header for a day's worth of transactions in the History list —
/// "Today" / "Yesterday" / "12 March" plus that day's net total.
class TransactionDateGroupHeader extends StatelessWidget {
  const TransactionDateGroupHeader({
    super.key,
    required this.date,
    required this.netTotal,
  });

  final DateTime date;
  final double netTotal;

  @override
  Widget build(BuildContext context) {
    final sign = netTotal >= 0 ? '+' : '-';
    // Semantic credit/debit color, not the lime brand accent — per the
    // color-usage rule, lime is reserved for CTAs/selected states/focus/
    // progress, never for amount text (see AppColors.credit/.debit).
    final color = netTotal >= 0 ? AppColors.credit : AppColors.debit;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xs,
        AppSizes.sm,
        AppSizes.xs,
        AppSizes.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            date.sectionLabel,
            style: context.textTheme.labelLarge?.copyWith(
              color: context.flowfi.textTertiary,
            ),
          ),
          FlowFiAmountText(
            '$sign${CurrencyFormatter.instance.format(netTotal.abs())}',
            size: AmountSize.body,
            color: color,
          ),
        ],
      ),
    );
  }
}
