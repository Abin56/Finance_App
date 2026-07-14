import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Section header for a day's worth of transactions in the History list —
/// "Today" / "Yesterday" / "12 March" plus that day's net total.
class TransactionDateGroupHeader extends StatelessWidget {
  const TransactionDateGroupHeader({super.key, required this.date, required this.netTotal});

  final DateTime date;
  final double netTotal;

  @override
  Widget build(BuildContext context) {
    final sign = netTotal >= 0 ? '+' : '-';
    final color = netTotal >= 0 ? context.colors.primary : context.colors.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.xs, AppSizes.md, AppSizes.xs, AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            date.sectionLabel,
            style: context.textTheme.labelLarge?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(
            '$sign${CurrencyFormatter.instance.format(netTotal.abs())}',
            style: context.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
