import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../../../features/transactions/domain/transaction.dart';
import '../../../../features/transactions/domain/transaction_type.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../../shared/widgets/animations/count_up_text.dart';
import '../../../../shared/widgets/charts/mini_trend_chart.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.netWorth] — the dashboard's hero card. Sums
/// every account's [Account.currentBalance] via the existing
/// [netWorthProvider] (never re-derives a figure Accounts/Reports already
/// own) and adds a 7-day net-cash-flow sparkline for an at-a-glance trend,
/// derived client-side from the same transaction stream every other
/// Dashboard stat already watches.
class NetWorthWidgetCard extends ConsumerStatefulWidget {
  const NetWorthWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  ConsumerState<NetWorthWidgetCard> createState() => _NetWorthWidgetCardState();
}

class _NetWorthWidgetCardState extends ConsumerState<NetWorthWidgetCard> {
  bool _hidden = false;

  /// Cumulative net (income − expense) for each of the last 7 days, oldest
  /// first — purely a display sparkline.
  List<double> _weeklyTrend(List<Transaction> transactions) {
    final today = DateTime.now().dateOnly;
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    var running = 0.0;
    return [
      for (final day in days)
        running += transactions
            .where((t) => t.dateTime.isSameDay(day))
            .fold(0.0, (sum, t) => sum + (t.type == TransactionType.income ? t.amount : -t.amount)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final netWorth = ref.watch(netWorthProvider);
    final transactions = ref.watch(calculableTransactionsProvider);
    final trend = _weeklyTrend(transactions);
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return DashboardWidgetGradientCard(
      onTap: () => context.push(AppRoutes.accounts),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Text(
                      widget.config.title,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSizes.xs),
                    InkWell(
                      onTap: () => setState(() => _hidden = !_hidden),
                      borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                      child: Icon(
                        _hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            _hidden
                ? Text(
                    '••••••',
                    style: context.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  )
                : CountUpText(
                    value: netWorth,
                    formatter: format.format,
                    style: context.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
            const SizedBox(height: AppSizes.lg),
            MiniTrendChart(values: trend, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
