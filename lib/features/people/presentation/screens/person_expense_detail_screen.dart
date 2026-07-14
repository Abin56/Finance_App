import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/expense_status_pill.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../expense/domain/expense.dart';
import '../../../expense/domain/expense_participant.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../expense/presentation/widgets/edit_expense_sheet.dart';
import '../../../expense/presentation/widgets/expense_updated_dialog.dart';
import '../../../expense/presentation/widgets/record_split_payment_sheet.dart';
import '../../../expense/presentation/widgets/settle_amount_sheet.dart';
import '../../../expense/presentation/widgets/share_expense.dart';
import '../../../expense/presentation/widgets/split_expense_checkbox_sheet.dart';
import '../../../transactions/domain/history_builder.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Figma "Expense Details" (frame 2) — the People flow's dedicated,
/// minimal per-expense screen: hero (icon/description/amount/status/date),
/// a small metadata grid, a plain-language "owes you" callout, the
/// operational Actions list (Edit / Add Payment / Split / Settle / Delete),
/// and a warning footer. Deliberately separate from the richer
/// `TransactionDetailScreen` (still used from History/dashboard), so the
/// People flow reads exactly like the mockup without gutting that screen.
class PersonExpenseDetailScreen extends ConsumerWidget {
  const PersonExpenseDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  static Future<void> open(BuildContext context, {required String transactionId}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PersonExpenseDetailScreen(transactionId: transactionId)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expense = ref.watch(expenseForTransactionProvider(transactionId));
    final transaction = (ref.watch(transactionsStreamProvider).value ?? const [])
        .where((t) => t.id == transactionId)
        .firstOrNull;

    if (expense == null || transaction == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final category = categories.where((c) => c.id == expense.categoryId).firstOrNull;
    final installments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final detail = HistoryBuilder.splitExpenseDetailFor(
      expense,
      {if (expense.scheduleId != null) expense.scheduleId!: installments},
    );

    final others = expense.participants.where((p) => !p.isMe).toList();
    final installmentById = {for (final i in installments) i.id: i};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Details'),
        actions: [
          if (expense.isSplit)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share expense',
              onPressed: () => ShareExpense.share(context, expense, installments),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: category == null
                            ? context.colors.primary.withValues(alpha: 0.15)
                            : Color(category.colorValue).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        category?.icon ?? Icons.receipt_long_outlined,
                        color: category == null ? context.colors.primary : Color(category.colorValue),
                        size: AppSizes.iconMd,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(child: Text(expense.description, style: context.textTheme.titleLarge)),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      CurrencyFormatter.instance.format(expense.totalAmount),
                      style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    ExpenseStatusPill(status: detail.status),
                  ],
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  '${transaction.dateTime.fullDate} • ${TimeOfDay.fromDateTime(transaction.dateTime).format(context)}',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: AppSizes.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSizes.md),
                _MetaRow(label: 'Paid by', value: 'You'),
                _MetaRow(label: 'Category', value: category?.name ?? 'Uncategorized'),
                if (expense.notes.isNotEmpty) _MetaRow(label: 'Note', value: expense.notes, isLast: true),
              ],
            ),
          ),
          if (others.length == 1) ...[
            const SizedBox(height: AppSizes.lg),
            _OwesYouCallout(
              name: others.single.name,
              remaining: installmentById[others.single.installmentId]?.remainingAmount ?? others.single.share,
            ),
          ],
          const SizedBox(height: AppSizes.lg),
          _ActionsCard(expense: expense, installments: installments),
          const SizedBox(height: AppSizes.lg),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: AppSizes.iconSm, color: AppColors.warning),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'Deleting this expense also removes all related payments. You can restore it from Trash.',
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.isLast = false});

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSizes.md),
      child: Row(
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
          const Spacer(),
          Flexible(
            child: Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _OwesYouCallout extends StatelessWidget {
  const _OwesYouCallout({required this.name, required this.remaining});

  final String name;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$name owes you', style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: AppSizes.xs),
          Text(
            CurrencyFormatter.instance.format(remaining),
            style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: context.colors.primary),
          ),
        ],
      ),
    );
  }
}

/// The Figma Actions list — Edit / Add Payment / Split / Settle / Delete,
/// in that order. Add Payment/Settle resolve a specific participant to
/// collect from (opening a chooser when the expense has more than one
/// collectible person), then show [ExpenseUpdatedDialog] on return.
class _ActionsCard extends ConsumerWidget {
  const _ActionsCard({required this.expense, required this.installments});

  final Expense expense;
  final List<Installment> installments;

  List<({ExpenseParticipant participant, Installment installment})> get _collectible {
    final byId = {for (final i in installments) i.id: i};
    return [
      for (final p in expense.participants)
        if (!p.isMe && p.installmentId != null && byId[p.installmentId] != null)
          if ((byId[p.installmentId]!).remainingAmount > 0)
            (participant: p, installment: byId[p.installmentId]!),
    ];
  }

  Future<void> _afterAction(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final refreshed = ref.read(expenseForTransactionProvider(expense.transactionId));
    if (refreshed != null) await ExpenseUpdatedDialog.show(context, expense: refreshed);
  }

  Future<({ExpenseParticipant participant, Installment installment})?> _chooseParticipant(BuildContext context) async {
    final options = _collectible;
    if (options.isEmpty) return null;
    if (options.length == 1) return options.single;
    return showModalBottomSheet<({ExpenseParticipant participant, Installment installment})>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Text('Who paid?', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final option in options)
              ListTile(
                title: Text(option.participant.name),
                trailing: Text(CurrencyFormatter.instance.format(option.installment.remainingAmount)),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCollectible = _collectible.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actions', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          _ActionRow(
            icon: Icons.edit_outlined,
            title: 'Edit Expense',
            onTap: () async {
              final result = await EditExpenseSheet.show(context, expense: expense);
              if (!context.mounted) return;
              // Deleted from the edit form → this expense no longer exists, so
              // close the detail screen instead of showing a success dialog.
              if (ref.read(expenseForTransactionProvider(expense.transactionId)) == null) {
                Navigator.of(context).pop();
                return;
              }
              if (result == true) await _afterAction(context, ref);
            },
          ),
          if (hasCollectible) ...[
            const Divider(height: AppSizes.lg),
            _ActionRow(
              icon: Icons.payments_outlined,
              title: 'Add Payment',
              subtitle: 'Add advance or partial payment',
              onTap: () async {
                final chosen = await _chooseParticipant(context);
                if (chosen == null || !context.mounted) return;
                final result = await RecordSplitPaymentSheet.show(
                  context,
                  expense: expense,
                  participant: chosen.participant,
                  installment: chosen.installment,
                );
                if (!context.mounted || result != true) return;
                await _afterAction(context, ref);
              },
            ),
          ],
          const Divider(height: AppSizes.lg),
          _ActionRow(
            icon: Icons.call_split_rounded,
            title: 'Split Expense',
            subtitle: 'Split this expense with others',
            onTap: () async {
              final result = await SplitExpenseCheckboxSheet.show(context, expense: expense);
              if (!context.mounted || result != true) return;
              await _afterAction(context, ref);
            },
          ),
          if (hasCollectible) ...[
            const Divider(height: AppSizes.lg),
            _ActionRow(
              icon: Icons.check_circle_outline_rounded,
              title: 'Settle Amount',
              subtitle: 'Mark as fully settled',
              onTap: () async {
                final chosen = await _chooseParticipant(context);
                if (chosen == null || !context.mounted) return;
                final result = await SettleAmountSheet.show(
                  context,
                  expense: expense,
                  participant: chosen.participant,
                  installment: chosen.installment,
                );
                if (!context.mounted || result != true) return;
                await _afterAction(context, ref);
              },
            ),
          ],
          const Divider(height: AppSizes.lg),
          _ActionRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete Expense',
            destructive: true,
            onTap: () async {
              final confirmed = await confirmDelete(context, entityName: 'Expense');
              if (!confirmed || !context.mounted) return;
              await ref.read(expenseRepositoryProvider).deleteExpense(expense);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.colors.error : context.colors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
            child: Icon(icon, color: color, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textTheme.titleMedium?.copyWith(color: destructive ? color : null)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                  ),
              ],
            ),
          ),
          if (!destructive) Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
