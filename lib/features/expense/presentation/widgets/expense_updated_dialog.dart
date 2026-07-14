import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/expense_status_pill.dart';
import '../../../transactions/domain/history_builder.dart';
import '../../domain/expense.dart';
import 'record_split_payment_sheet.dart';
import 'settle_amount_sheet.dart';
import 'split_expense_form_sheet.dart';

/// Figma "Expense Updated" (frame 7) — the success confirmation shown after
/// an Edit/Add Payment/Split/Settle save. Checkmark, a recap of the
/// expense's current standing (same [ExpenseStatusPill]/status math every
/// other expense surface uses, via [HistoryBuilder.splitExpenseDetailFor]),
/// a compact set of next-action shortcuts, and `Done`. The shortcuts pop
/// this dialog then open the corresponding flow directly (Add Payment/Settle
/// only when a single collectible participant still has a remaining amount).
class ExpenseUpdatedDialog extends ConsumerWidget {
  const ExpenseUpdatedDialog({super.key, required this.expense});

  final Expense expense;

  static Future<void> show(BuildContext context, {required Expense expense}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ExpenseUpdatedDialog(expense: expense),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final detail = HistoryBuilder.splitExpenseDetailFor(
      expense,
      {if (expense.scheduleId != null) expense.scheduleId!: installments},
    );

    final installmentById = {for (final i in installments) i.id: i};
    final collectible = expense.participants.where((p) => !p.isMe && p.installmentId != null).toList();
    final single = collectible.length == 1 ? collectible.single : null;
    final singleInstallment = single == null ? null : installmentById[single.installmentId];
    final canCollect = singleInstallment != null && singleInstallment.remainingAmount > 0;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
            const SizedBox(height: AppSizes.md),
            Text(
              'Expense updated successfully!',
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSizes.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.description, style: context.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Amount', style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
                      Text(CurrencyFormatter.instance.format(expense.totalAmount), style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status', style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
                      ExpenseStatusPill(status: detail.status, compact: true),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Actions', style: context.textTheme.titleSmall),
            ),
            const SizedBox(height: AppSizes.xs),
            if (canCollect)
              _ShortcutRow(
                icon: Icons.payments_outlined,
                label: 'Add Payment',
                onTap: () {
                  Navigator.of(context).pop();
                  RecordSplitPaymentSheet.show(context, expense: expense, participant: single!, installment: singleInstallment);
                },
              ),
            _ShortcutRow(
              icon: Icons.call_split_rounded,
              label: 'Split Expense',
              onTap: () {
                Navigator.of(context).pop();
                SplitExpenseFormSheet.show(context, editing: expense, assignOnly: collectible.length == 1);
              },
            ),
            if (canCollect)
              _ShortcutRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'Settle Amount',
                onTap: () {
                  Navigator.of(context).pop();
                  SettleAmountSheet.show(context, expense: expense, participant: single!, installment: singleInstallment);
                },
              ),
            const SizedBox(height: AppSizes.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            Icon(icon, size: AppSizes.iconSm, color: context.colors.primary),
            const SizedBox(width: AppSizes.md),
            Text(label, style: context.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
