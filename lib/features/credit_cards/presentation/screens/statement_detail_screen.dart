import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/presentation/widgets/transaction_date_group_header.dart';
import '../../../transactions/presentation/widgets/transaction_tile.dart';
import '../../domain/statement_status.dart';
import '../providers/credit_card_providers.dart';
import '../widgets/record_statement_payment_sheet.dart';
import '../widgets/statement_fees_sheet.dart';

/// One statement's full detail per the milestone spec: Statement Period,
/// Generated, Due, Total, Minimum Due, Paid, Remaining, Status, then every
/// transaction inside the window grouped by date — reuses
/// [TransactionDateGroupHeader]/[TransactionTile] exactly as the main
/// Transactions/History screens do, so a statement's transaction list looks
/// identical to every other transaction list in the app.
class StatementDetailScreen extends ConsumerWidget {
  const StatementDetailScreen({super.key, required this.cardId, required this.statementId});

  final String cardId;
  final String statementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statements = ref.watch(statementsStreamProvider(cardId)).value ?? const [];
    final statement = statements.where((s) => s.id == statementId).firstOrNull;
    if (statement == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cardTransactions = ref.watch(transactionsForCardProvider(cardId));
    final periodTransactions = cardTransactions.where((t) => !t.isDeleted && statement.contains(t.dateTime)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final accounts = ref.watch(accountForCardProvider(cardId));
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};

    final byDay = <DateTime, List<dynamic>>{};
    for (final transaction in periodTransactions) {
      final day = DateTime(transaction.dateTime.year, transaction.dateTime.month, transaction.dateTime.day);
      byDay.putIfAbsent(day, () => []).add(transaction);
    }
    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    final status = statement.status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statement'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Log interest & late fees',
            onPressed: () => StatementFeesSheet.show(context, cardId: cardId, statement: statement),
          ),
        ],
      ),
      floatingActionButton: statement.remainingAmount <= 0
          ? null
          : FloatingActionButton.extended(
              heroTag: 'statement_detail_fab',
              onPressed: () => RecordStatementPaymentSheet.show(context, cardId: cardId, statement: statement),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Pay'),
            ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statement Period', style: context.textTheme.bodySmall),
                    _StatusBadge(status: status),
                  ],
                ),
                Text(
                  '${statement.periodStart.day}/${statement.periodStart.month} → ${statement.periodEnd.day}/${statement.periodEnd.month}',
                  style: context.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSizes.sm),
                _DetailRow(label: 'Generated', value: '${statement.generatedDate.day}/${statement.generatedDate.month}'),
                _DetailRow(label: 'Due', value: '${statement.dueDate.day}/${statement.dueDate.month}'),
                const Divider(height: AppSizes.lg),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryStat(label: 'Total', value: statement.totalAmount),
                    ),
                    if (statement.minimumDue != null)
                      Expanded(
                        child: _SummaryStat(label: 'Minimum Due', value: statement.minimumDue!),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryStat(label: 'Paid', value: statement.amountPaid, color: AppColors.success),
                    ),
                    Expanded(
                      child: _SummaryStat(label: 'Remaining', value: statement.remainingAmount, color: status.color),
                    ),
                  ],
                ),
                if (statement.interestCharged != null || statement.lateFee != null) ...[
                  const Divider(height: AppSizes.lg),
                  Row(
                    children: [
                      if (statement.interestCharged != null)
                        Expanded(child: _SummaryStat(label: 'Interest', value: statement.interestCharged!)),
                      if (statement.lateFee != null)
                        Expanded(child: _SummaryStat(label: 'Late fee', value: statement.lateFee!)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Transactions', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          if (periodTransactions.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions',
              subtitle: 'Purchases in this billing cycle will show up here.',
            )
          else
            for (final day in sortedDays) ...[
              TransactionDateGroupHeader(
                date: day,
                netTotal: -byDay[day]!.fold(0.0, (sum, t) => sum + (t.amount as double)),
              ),
              for (final transaction in byDay[day]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: TransactionTile(
                    transaction: transaction,
                    category: categoriesById[transaction.categoryId],
                    account: accounts,
                    onTap: () => context.push('${AppRoutes.transactions}/${transaction.id}'),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          Text(value, style: context.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final StatementStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        status.label,
        style: context.textTheme.labelMedium?.copyWith(color: status.color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
