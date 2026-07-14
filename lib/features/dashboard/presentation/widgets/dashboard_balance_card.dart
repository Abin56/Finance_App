import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/animations/count_up_text.dart';
import '../../../../shared/widgets/charts/mini_trend_chart.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Net worth headline card — total balance across every account, plus how
/// much that's changed since last month (in absolute and percentage terms),
/// and a 7-day net-cash-flow sparkline for an at-a-glance trend. The "vs
/// last month" comparison is a snapshot delta ([netWorth] now vs. last
/// month's account balances aren't tracked historically, so this reads the
/// month's net transaction flow instead — the same number
/// [DashboardMonthlySummaryCards]/[CategoryBreakdownCard] already derive
/// client-side from the live transaction stream).
class DashboardBalanceCard extends ConsumerStatefulWidget {
  const DashboardBalanceCard({super.key, required this.changeVsLastMonth, required this.changePercent});

  final double changeVsLastMonth;

  /// Null when last month had no activity to compare against (avoids a
  /// divide-by-zero percentage).
  final double? changePercent;

  @override
  ConsumerState<DashboardBalanceCard> createState() => _DashboardBalanceCardState();
}

class _DashboardBalanceCardState extends ConsumerState<DashboardBalanceCard> {
  bool _hidden = false;

  /// Cumulative net (income − expense) for each of the last 7 days, oldest
  /// first — purely a display sparkline, derived client-side from the same
  /// transaction stream every other Dashboard stat already watches (no new
  /// data source).
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
    final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
    final positive = widget.changeVsLastMonth >= 0;
    final trend = _weeklyTrend(transactions);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.primaryGradient,
        ),
        boxShadow: AppShadows.soft(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.accounts),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Total Balance',
                          style: context.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        const SizedBox(width: AppSizes.xs),
                        InkWell(
                          onTap: () => setState(() => _hidden = !_hidden),
                          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                          child: Icon(
                            _hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: AppSizes.iconSm,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.85)),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                _hidden
                    ? Text(
                        '••••••',
                        style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                      )
                    : CountUpText(
                        value: netWorth,
                        formatter: CurrencyFormatter.instance.format,
                        style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                const SizedBox(height: AppSizes.md),
                if (widget.changePercent != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: AppSizes.iconSm,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${CurrencyFormatter.instance.format(widget.changeVsLastMonth.abs())} '
                          '(${widget.changePercent!.abs().toStringAsFixed(2)}%)',
                          style: context.textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSizes.lg),
                MiniTrendChart(values: trend, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
