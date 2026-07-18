import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/expense_status_pill.dart';
import '../../../../shared/widgets/states/transaction_flag_badge.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../expense/domain/expense.dart';
import '../../../expense/domain/expense_participant.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../expense/presentation/widgets/expense_updated_dialog.dart';
import '../../../expense/presentation/widgets/record_split_payment_sheet.dart';
import '../../../expense/presentation/widgets/settle_amount_sheet.dart';
import '../../../expense/presentation/widgets/share_expense.dart';
import '../../../expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../domain/history_builder.dart';
import '../../domain/transaction.dart';
import '../../domain/transaction_type.dart';
import '../providers/transaction_providers.dart';
import 'add_expense_screen.dart';

/// One transaction's full detail. When it's the account-balance effect of a
/// split/assigned [Expense] (see `Expense.transactionId`), also shows the
/// participants, each one's share, who paid, and their live pending/
/// collected status — reusing the same `Expense`/`Installment` data the
/// Split Expenses and Person Statement screens already load, no duplicated
/// business logic.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    if (transactionsAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final transactions = transactionsAsync.value ?? const [];
    final transaction = transactions.where((t) => t.id == transactionId).firstOrNull;

    if (transaction == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Transaction not found',
          subtitle: 'This transaction may have been deleted.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go Back'),
          ),
        ),
      );
    }

    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final account = accounts.where((a) => a.id == transaction.accountId).firstOrNull;
    final category = categories.where((c) => c.id == transaction.categoryId).firstOrNull;
    final expense = ref.watch(expenseForTransactionProvider(transactionId));

    /// Part 1/2 — an existing plain, unsplit, or single-assigned expense can
    /// still be turned into (or re-assigned as) a split/assignment via
    /// `convertToSplit`/`convertToAssigned` (both guard against re-converting
    /// an already-split expense). An already-split expense instead gets the
    /// "Edit shared expense" pencil (`SplitExpenseFormSheet(editing: ...)`,
    /// via `ExpenseRepository.editExpense`) — same destination, different
    /// entry point, since editing shares/amount is not the same operation as
    /// converting a plain transaction for the first time. See
    /// [Expense.canReassign] for the (unit-tested) rule itself.
    final canReassign = Expense.canReassign(
      expense: expense,
      isExpenseTransaction: transaction.type == TransactionType.expense,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (canReassign)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Assign to person',
              onPressed: () => _assignToPerson(context, ref, transaction, expense),
            ),
          if (canReassign)
            IconButton(
              icon: const Icon(Icons.call_split_rounded),
              tooltip: 'Split this expense',
              onPressed: () => _splitExpense(context, ref, transaction, expense),
            ),
          if (expense != null && expense.isSplit)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share expense',
              onPressed: () => ShareExpense.share(
                context,
                expense,
                expense.scheduleId == null
                    ? const []
                    : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [],
              ),
            ),
          if (expense == null || !expense.isSplit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit transaction',
              onPressed: () => AddExpenseScreen.show(context, transaction: transaction),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          _TransactionHeroCard(transaction: transaction, accountName: account?.name, categoryName: category?.name),
          if (canReassign) ...[
            const SizedBox(height: AppSizes.lg),
            _ConvertToSplitCard(
              onAssign: () => _assignToPerson(context, ref, transaction, expense),
              onSplit: () => _splitExpense(context, ref, transaction, expense),
            ),
          ] else if (transaction.type != TransactionType.expense) ...[
            const SizedBox(height: AppSizes.lg),
            const _ReassignUnavailableNotice(
              reason: 'Only expenses can be assigned to a person or split — this is an income transaction.',
            ),
          ],
          if (expense != null) ...[
            const SizedBox(height: AppSizes.lg),
            if (expense.isSplit) _AlreadyLinkedNotice(expense: expense),
            if (expense.isSplit) const SizedBox(height: AppSizes.lg),
            if (expense.isSplit) _OwesYouCallout(expense: expense),
            if (expense.isSplit) const SizedBox(height: AppSizes.lg),
            _SplitSummaryCard(expense: expense),
            if (expense.isSplit) ...[
              const SizedBox(height: AppSizes.lg),
              _ExpenseActionsCard(expense: expense),
            ],
            const SizedBox(height: AppSizes.lg),
            _ParticipantsSection(expense: expense),
            const SizedBox(height: AppSizes.lg),
            _SettlementHistorySection(expense: expense),
          ],
        ],
      ),
    );
  }

  ConvertToSplitPrefill _prefillFor(Transaction transaction) => ConvertToSplitPrefill(
        transactionId: transaction.id,
        description: transaction.notes.isNotEmpty ? transaction.notes : 'Expense',
        totalAmount: transaction.amount,
        date: transaction.dateTime,
        categoryId: transaction.categoryId,
        accountId: transaction.accountId,
        notes: transaction.notes,
      );

  /// Opens [SplitExpenseFormSheet] pre-filled from this transaction's own
  /// fields — Part 2's "split an existing expense" flow. Works whether this
  /// transaction has no `Expense` doc yet, a plain unsplit one, or a
  /// single-assigned one (see `canReassign`); [existingExpense] — when
  /// non-null — is passed through so `ExpenseRepository.convertToSplit`
  /// updates that same document in place instead of creating a new one.
  /// Never creates a second `Transaction` either way. Shows
  /// [ExpenseUpdatedDialog] afterward with the freshly-saved `Expense`, read
  /// via [ref] rather than reusing the (possibly now-stale) [existingExpense]
  /// closure value.
  Future<void> _splitExpense(BuildContext context, WidgetRef ref, Transaction transaction, Expense? existingExpense) async {
    final result = await SplitExpenseFormSheet.show(
      context,
      convertFrom: _prefillFor(transaction),
      existingExpense: existingExpense,
    );
    if (!context.mounted || result != true) return;
    final saved = ref.read(expenseForTransactionProvider(transaction.id));
    if (saved != null) await ExpenseUpdatedDialog.show(context, expense: saved);
  }

  /// Opens [SplitExpenseFormSheet] in `assignOnly` mode — Part 1's "assign
  /// an existing expense to a person" flow. Same prefill/existingExpense
  /// plumbing as [_splitExpense]; saving calls
  /// `ExpenseRepository.convertToAssigned` instead.
  Future<void> _assignToPerson(BuildContext context, WidgetRef ref, Transaction transaction, Expense? existingExpense) async {
    final result = await SplitExpenseFormSheet.show(
      context,
      convertFrom: _prefillFor(transaction),
      existingExpense: existingExpense,
      assignOnly: true,
    );
    if (!context.mounted || result != true) return;
    final saved = ref.read(expenseForTransactionProvider(transaction.id));
    if (saved != null) await ExpenseUpdatedDialog.show(context, expense: saved);
  }
}

/// Prompt shown on a reassignable expense transaction (no linked `Expense`
/// yet, a plain unsplit one, or a single-assigned one) — Part 1/2's
/// discoverable "assign or split an old expense" entry point, mirroring the
/// AppBar actions for anyone scrolling the detail body instead of checking
/// the toolbar. Offers both actions since either is valid at this point.
class _ConvertToSplitCard extends StatelessWidget {
  const _ConvertToSplitCard({required this.onAssign, required this.onSplit});

  final VoidCallback onAssign;
  final VoidCallback onSplit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReassignRow(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Assign to person',
            subtitle: 'This expense was really for someone else — assign it to them.',
            onTap: onAssign,
          ),
          const Divider(height: AppSizes.lg),
          _ReassignRow(
            icon: Icons.call_split_rounded,
            title: 'Split this expense',
            subtitle: 'Share this expense with others and track who still needs to pay.',
            onTap: onSplit,
          ),
        ],
      ),
    );
  }
}

/// Explains why the AppBar shows only the edit pencil and no
/// assign/split icons, for transaction types that can never be
/// assigned/split (income) — a silent absence otherwise reads as a bug
/// report waiting to happen (see the "can't assign old expenses" report
/// that turned out to be a mislabeled income transaction).
class _ReassignUnavailableNotice extends StatelessWidget {
  const _ReassignUnavailableNotice({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              reason,
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains why the AppBar shows "Edit shared expense" instead of
/// "Assign to person"/"Split this expense" — this expense is already
/// linked, so those actions would create a duplicate rather than convert
/// this transaction. Names who it's already with, so "why did the icons
/// disappear" never has to be answered by re-reading the summary card
/// further down the page.
class _AlreadyLinkedNotice extends StatelessWidget {
  const _AlreadyLinkedNotice({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final others = expense.participants.where((p) => !p.isMe).toList();
    final reason = others.length == 1
        ? 'Already assigned to ${others.single.name}.'
        : 'Already split between ${others.length} people.';

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: AppSizes.iconSm, color: context.colors.primary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              '$reason Use Edit Expense below to change the amount, participants, or shares.',
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain-language restatement of the amount using the *other* participant's
/// name instead of "remaining" — Figma's "Rahul Sharma owes you ₹1,200"
/// pattern. Only rendered for the common single-other-participant case
/// (an assignment, or a 2-way split); a genuine multi-person split has no
/// single "owes you" framing, so [_SplitSummaryCard]'s existing "Paid by
/// you" text covers that case instead.
class _OwesYouCallout extends ConsumerWidget {
  const _OwesYouCallout({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final others = expense.participants.where((p) => !p.isMe).toList();
    if (others.length != 1) return const SizedBox.shrink();
    final other = others.single;

    final installments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final installment = installments.where((i) => i.id == other.installmentId).firstOrNull;
    final remaining = installment?.remainingAmount ?? other.share;
    if (remaining <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Text.rich(
        TextSpan(
          style: context.textTheme.bodyLarge,
          children: [
            TextSpan(text: other.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' owes you '),
            TextSpan(
              text: CurrencyFormatter.instance.format(remaining),
              style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Figma "Expense Details" Actions list — Edit/Add Payment/Settle/
/// Delete, in that order, for an already-split/assigned expense (an
/// unsplit transaction still uses [_ConvertToSplitCard] instead). Add
/// Payment/Settle Amount only appear for the common single-collectible-
/// participant case (an assignment, or a 2-way split with one other
/// person) — reusing [_ParticipantCard]'s own per-participant "Collect" tap
/// covers the general multi-person case without a second picker UI.
class _ExpenseActionsCard extends ConsumerWidget {
  const _ExpenseActionsCard({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final installmentById = {for (final i in installments) i.id: i};
    final collectible = expense.participants.where((p) => !p.isMe && p.installmentId != null).toList();
    final single = collectible.length == 1 ? collectible.single : null;
    final singleInstallment = single == null ? null : installmentById[single.installmentId];
    final canCollect = singleInstallment != null && singleInstallment.remainingAmount > 0;

    Future<void> showUpdatedDialog() async {
      if (!context.mounted) return;
      final refreshed = ref.read(expenseForTransactionProvider(expense.transactionId));
      if (refreshed != null) await ExpenseUpdatedDialog.show(context, expense: refreshed);
    }

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
              final result = await SplitExpenseFormSheet.show(context, editing: expense, assignOnly: collectible.length == 1);
              if (result == true) await showUpdatedDialog();
            },
          ),
          if (canCollect) ...[
            const Divider(height: AppSizes.lg),
            _ActionRow(
              icon: Icons.payments_outlined,
              title: 'Add Payment',
              subtitle: 'Add advance or partial payment',
              onTap: () async {
                final result = await RecordSplitPaymentSheet.show(
                  context,
                  expense: expense,
                  participant: single!,
                  installment: singleInstallment,
                );
                if (result == true) await showUpdatedDialog();
              },
            ),
            const Divider(height: AppSizes.lg),
            _ActionRow(
              icon: Icons.check_circle_outline_rounded,
              title: 'Settle Amount',
              subtitle: 'Mark as fully settled',
              onTap: () async {
                final result = await SettleAmountSheet.show(
                  context,
                  expense: expense,
                  participant: single!,
                  installment: singleInstallment,
                );
                if (result == true) await showUpdatedDialog();
              },
            ),
          ],
          const Divider(height: AppSizes.lg),
          _ActionRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete Expense',
            destructive: true,
            onTap: () => _deleteExpense(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExpense(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDelete(context, entityName: 'Expense');
    if (!confirmed || !context.mounted) return;
    await ref.read(expenseRepositoryProvider).deleteExpense(expense);
    if (context.mounted) Navigator.of(context).pop();
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
  final VoidCallback onTap;

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
          Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

class _ReassignRow extends StatelessWidget {
  const _ReassignRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(icon, color: context.colors.primary, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textTheme.titleMedium),
                Text(
                  subtitle,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

/// The transaction's headline card — large signed amount up top (the number
/// that matters most, per the app's visual-hierarchy rule), then a clean
/// icon-led grid of its supporting facts (date/account/category/note)
/// instead of a plain label:value list.
class _TransactionHeroCard extends ConsumerWidget {
  const _TransactionHeroCard({required this.transaction, required this.accountName, required this.categoryName});

  final Transaction transaction;
  final String? accountName;
  final String? categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = transaction.type == TransactionType.income;
    final sign = isIncome ? '+' : '-';
    final color = transaction.type.color;
    final linkedPersonId = transaction.linkedPersonId;
    final linkedPersonName = linkedPersonId == null
        ? null
        : (ref.watch(peopleStreamProvider).value ?? const [])
            .where((p) => p.id == linkedPersonId)
            .firstOrNull
            ?.name;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(transaction.type.icon, color: color, size: AppSizes.iconMd),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.type.label,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      '$sign${CurrencyFormatter.instance.format(transaction.amount)}',
                      style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (transaction.excludeFromCalculations || transaction.accountingMonth != null) ...[
            const SizedBox(height: AppSizes.sm),
            TransactionFlagBadge(
              excludeFromCalculations: transaction.excludeFromCalculations,
              date: transaction.dateTime,
              accountingMonth: transaction.accountingMonth,
            ),
          ],
          const SizedBox(height: AppSizes.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.lg),
          _DetailGridRow(icon: Icons.event_outlined, label: 'Transaction Date', value: transaction.dateTime.fullDate),
          if (transaction.accountingMonth != null)
            _DetailGridRow(
              icon: Icons.calendar_month_outlined,
              label: 'Accounting Month',
              value: transaction.accountingMonth!.monthYear,
            ),
          _DetailGridRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Account',
            value: accountName ?? 'Unknown account',
          ),
          _DetailGridRow(
            icon: Icons.sell_outlined,
            label: 'Category',
            value: categoryName ?? 'Uncategorized',
            isLast: transaction.notes.isEmpty && linkedPersonName == null,
          ),
          if (linkedPersonName != null)
            _DetailGridRow(
              icon: Icons.person_outline_rounded,
              label: 'Person',
              value: linkedPersonName,
              isLast: transaction.notes.isEmpty,
              onTap: () => context.push('${AppRoutes.people}/${transaction.linkedPersonId}'),
            ),
          if (transaction.notes.isNotEmpty)
            _DetailGridRow(icon: Icons.notes_rounded, label: 'Note', value: transaction.notes, isLast: true),
        ],
      ),
    );
  }
}

class _DetailGridRow extends StatelessWidget {
  const _DetailGridRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  /// Set only for rows that link elsewhere (currently just "Person" — see
  /// [_TransactionHeroCard]) — every other row stays plain text.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: AppSizes.sm),
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: onTap == null ? null : context.colors.primary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: context.colors.primary),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppSizes.radiusMd), child: row);
  }
}

/// The split expense's headline card — total/collected/remaining at a
/// glance, an animated settlement progress bar, and who fronted the money.
/// Deliberately separate from [_ParticipantsSection] so the "how are we
/// doing overall" story reads before "who specifically owes what".
class _SplitSummaryCard extends ConsumerWidget {
  const _SplitSummaryCard({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];

    final collected = installments.fold(0.0, (sum, i) => sum + i.amountPaid);
    final remaining = installments.fold(0.0, (sum, i) => sum + i.remainingAmount);
    final progress = expense.totalAmount <= 0 ? 0.0 : (collected / expense.totalAmount).clampedProgress;
    final detail = HistoryBuilder.splitExpenseDetailFor(
      expense,
      {if (expense.scheduleId != null) expense.scheduleId!: installments},
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.participants.length == 1 ? 'This Person Will Pay' : 'Share Expense',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(expense.description, style: context.textTheme.titleLarge),
                  ],
                ),
              ),
              ExpenseStatusPill(status: detail.status),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Paid by you',
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: AppSizes.lg),
          ProgressBar(progress: progress, label: 'Paid · ${progress.asPercent}'),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Expanded(child: _SummaryStat(label: 'Total', value: expense.totalAmount)),
              _SummaryStatDivider(),
              Expanded(
                child: _SummaryStat(label: 'Received', value: collected, color: AppColors.success),
              ),
              _SummaryStatDivider(),
              Expanded(
                child: _SummaryStat(label: 'Amount Left', value: remaining, color: remaining > 0 ? AppColors.pending : null),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Expanded(child: _SummaryStat(label: 'My Share', value: expense.myShare)),
              _SummaryStatDivider(),
              Expanded(child: _SummaryStat(label: "Others' Share", value: expense.othersShare)),
            ],
          ),
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
        const SizedBox(height: 2),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SummaryStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      color: context.colors.outline.withValues(alpha: 0.5),
    );
  }
}

/// Every participant as its own premium card — avatar, share, live status,
/// a mini progress bar, and (when still owed) a one-tap "Collect" action
/// straight into [RecordSplitPaymentSheet], scoped to that participant's
/// own tracking installment.
class _ParticipantsSection extends StatelessWidget {
  const _ParticipantsSection({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSizes.xs, bottom: AppSizes.sm),
          child: Text('People', style: context.textTheme.titleMedium),
        ),
        for (final participant in expense.participants)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.sm),
            child: _ParticipantCard(expense: expense, participant: participant),
          ),
      ],
    );
  }
}

class _ParticipantCard extends ConsumerWidget {
  const _ParticipantCard({required this.expense, required this.participant});

  final Expense expense;
  final ExpenseParticipant participant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installment = participant.installmentId == null || expense.scheduleId == null
        ? null
        : (ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const <Installment>[])
            .where((i) => i.id == participant.installmentId)
            .firstOrNull;

    final status = installment?.status;
    final statusColor = status?.color ?? context.colors.onSurface.withValues(alpha: 0.4);
    final progress = installment == null || installment.amountDue <= 0
        ? 0.0
        : (installment.amountPaid / installment.amountDue).clampedProgress;
    final canCollect = installment != null && installment.remainingAmount > 0;

    return AppCard(
      onTap: canCollect
          ? () => RecordSplitPaymentSheet.show(context, expense: expense, participant: participant, installment: installment)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: participant.name, colorValue: _colorFor(participant).toARGB32(), radius: 20),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant.name,
                      style: context.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      participant.isMe ? 'Your share' : (status == null ? 'Not tracked' : status.label),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: participant.isMe ? context.colors.onSurface.withValues(alpha: 0.6) : statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(participant.share),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (canCollect)
                    Text(
                      'Record Payment',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: context.colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (installment != null && status != InstallmentStatus.paid) ...[
            const SizedBox(height: AppSizes.md),
            ProgressBar(progress: progress, height: 6),
          ],
        ],
      ),
    );
  }

  /// Deterministic pseudo-color from the participant's name so untracked
  /// participants (no linked [Person], no `avatarColorValue`) still get a
  /// stable, distinct avatar color instead of every one looking identical.
  Color _colorFor(ExpenseParticipant participant) {
    final hash = participant.name.codeUnits.fold(0, (sum, c) => sum + c);
    return AppColors.categoryPalette[hash % AppColors.categoryPalette.length];
  }
}

/// Every [InstallmentPayment] across every participant's tracking
/// installment, newest first — the split expense's settlement history,
/// styled like `EmiPaymentHistoryTile`/`LedgerTimelineTile` so every
/// payment timeline in the app reads consistently.
class _SettlementHistorySection extends ConsumerWidget {
  const _SettlementHistorySection({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (expense.scheduleId == null) return const SizedBox.shrink();

    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final participantByInstallmentId = {
      for (final p in expense.participants)
        if (p.installmentId != null) p.installmentId!: p,
    };

    final payments = <(InstallmentPayment, ExpenseParticipant)>[];
    for (final installment in installments) {
      final participant = participantByInstallmentId[installment.id];
      if (participant == null) continue;
      final installmentPayments = ref
              .watch(installmentPaymentsStreamProvider((scheduleId: expense.scheduleId!, installmentId: installment.id)))
              .value ??
          const [];
      for (final payment in installmentPayments) {
        payments.add((payment, participant));
      }
    }
    payments.sort((a, b) => b.$1.date.compareTo(a.$1.date));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Records', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          if (payments.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No payments yet',
              subtitle: 'Payments people make toward this expense will show up here.',
            )
          else
            for (final (payment, participant) in payments)
              _SettlementTile(payment: payment, participant: participant),
        ],
      ),
    );
  }
}

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.payment, required this.participant});

  final InstallmentPayment payment;
  final ExpenseParticipant participant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(participant.name, style: context.textTheme.bodyMedium),
                Text(
                  payment.note.isNotEmpty ? '${payment.date.shortDate} · ${payment.note}' : payment.date.shortDate,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.instance.format(payment.amount),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}
