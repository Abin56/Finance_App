import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../reports/domain/reports_period.dart';
import '../../domain/cash_flow_period.dart';
import '../../domain/money_flow_line.dart';
import '../providers/cash_flow_providers.dart';

/// Which of the two Cash Flow Summary totals this detail screen explains —
/// drives the title, color, and which line provider is read.
enum MoneyFlowDirection { moneyIn, moneyOut }

/// The Money In / Money Out drill-down — shows every [MoneyFlowLine] behind
/// whichever total the user tapped on [CashFlowSummaryCard], for the exact
/// same selected [cashFlowDateRangeProvider] range. Reads
/// [moneyInLinesForRangeProvider]/[moneyOutLinesForRangeProvider] directly
/// (never a separate total) so this screen's own footer total is
/// mathematically guaranteed to equal the summary figure that opened it —
/// they're both sums of the same list.
class MoneyFlowDetailScreen extends ConsumerWidget {
  const MoneyFlowDetailScreen({super.key, required this.direction});

  final MoneyFlowDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(cashFlowDateRangeProvider);
    final range = ref.watch(resolvedCashFlowRangeProvider);
    final lines = direction == MoneyFlowDirection.moneyIn
        ? ref.watch(moneyInLinesForRangeProvider)
        : ref.watch(moneyOutLinesForRangeProvider);
    final total = lines.fold(0.0, (sum, l) => sum + l.amount);
    final isIn = direction == MoneyFlowDirection.moneyIn;
    final color = isIn ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppClay.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          isIn ? 'Money In' : 'Money Out',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.md),
              child: ClayCard(
                padding: const EdgeInsets.all(AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rangeLabel(period, range),
                      style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      CurrencyFormatter.instance.format(total),
                      style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? EmptyState(
                      icon: isIn ? Icons.call_received_rounded : Icons.call_made_rounded,
                      title: isIn ? 'No money received during this period' : 'No money spent during this period',
                      subtitle: 'Nothing contributed to ${isIn ? 'Money In' : 'Money Out'} for the selected range.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.fabClearance),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final showDateHeader = index == 0 || !lines[index - 1].date.isSameDay(line.date);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showDateHeader)
                              Padding(
                                padding: EdgeInsets.only(top: index == 0 ? 0 : AppSizes.md, bottom: AppSizes.xs),
                                child: Text(
                                  line.date.sectionLabel,
                                  style: context.textTheme.labelLarge?.copyWith(
                                    color: context.colors.onSurface.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            _MoneyFlowLineTile(line: line, color: color),
                          ],
                        );
                      },
                    ),
            ),
            if (lines.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border(top: BorderSide(color: context.colors.outlineVariant)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      CurrencyFormatter.instance.format(total),
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _rangeLabel(CashFlowPeriod period, DateRange range) {
    if (period.preset != CashFlowPreset.custom) return period.preset.label;
    return '${range.start.shortDate} – ${range.end.shortDate}';
  }
}

class _MoneyFlowLineTile extends StatelessWidget {
  const _MoneyFlowLineTile({required this.line, required this.color});

  final MoneyFlowLine line;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (line.categoryLabel != null) line.categoryLabel!,
      if (line.accountLabel != null) line.accountLabel!,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title,
                  style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join(' · '),
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.instance.format(line.amount),
                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
              Text(
                line.kind.label,
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
