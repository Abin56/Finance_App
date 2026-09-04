import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../shared/widgets/dialogs/add_entry_menu.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/anchored_sort_menu.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../expense/domain/expense.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../../../sms_inbox/presentation/screens/sms_inbox_screen.dart';
import '../../data/transaction_repository.dart';
import '../../domain/history_entry.dart';
import '../../domain/transaction.dart' as domain;
import '../providers/history_providers.dart';
import '../providers/transaction_providers.dart';
import '../widgets/history_filter_chips.dart';
import '../widgets/history_tile.dart';
import '../widgets/transaction_date_group_header.dart';
import '../widgets/transaction_filter.dart';
import '../widgets/transaction_filter_sheet.dart';
import '../widgets/transaction_tile.dart';
import 'transactions_trash_screen.dart';

/// Unified History — every plain transaction, split expense, loan/bill/EMI
/// payment, and money-received receipt in one feed, filterable by
/// [HistoryFilter]. [HistoryFilter.all]/[HistoryFilter.transactions] keep
/// the original transaction-only search/filter/sort/date-grouped/dismiss-to-
/// trash experience unchanged; every other category renders the unified
/// (read-only, tap-to-open) [HistoryEntry] feed from [historyEntriesProvider]
/// instead, since those entries don't live in the Transactions collection
/// and so can't be edited/trashed the same way.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, this.initialFilterName, this.initialAccountId});

  /// A [HistoryFilter] enum name (e.g. `'splitExpenses'`) supplied via the
  /// `?filter=` query param — lets other screens (the dashboard's "Money to
  /// collect" card) deep-link straight into a pre-filtered History instead
  /// of duplicating History's own filtering logic.
  final String? initialFilterName;

  /// Pre-seeds [TransactionFilter.accountId] — lets Account Details push
  /// straight into History scoped to one account, exactly as if the user
  /// had opened Filters and picked that account themselves. Clearing
  /// filters from here behaves like any other manually-applied filter.
  final String? initialAccountId;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  late TransactionFilter _filter = TransactionFilter(accountId: widget.initialAccountId);
  TransactionSort _sort = TransactionSort.dateDesc;
  late HistoryFilter _historyFilter = HistoryFilter.values.firstWhere(
    (f) => f.name == widget.initialFilterName,
    orElse: () => HistoryFilter.all,
  );
  final _sortFieldKey = GlobalKey();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await TransactionFilterSheet.show(context, _filter);
    if (result != null) setState(() => _filter = result);
  }

  /// The "Date Range" field's own direct picker — narrower than
  /// [_openFilters] (type/account/category/date all at once), so a user who
  /// only wants to change dates isn't dropped into the full filter sheet to
  /// do it.
  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _filter.startDate != null && _filter.endDate != null
          ? DateTimeRange(start: _filter.startDate!, end: _filter.endDate!)
          : null,
    );
    if (picked == null) return;
    setState(() => _filter = _filter.copyWith(startDate: picked.start, endDate: picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(transactionRepositoryProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final accountsById = {for (final a in accounts) a.id: a};
    final categoriesById = {for (final c in categories) c.id: c};
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final peopleById = {for (final p in people) p.id: p};

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
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search notes, category, account…',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_rounded, size: AppSizes.iconSm, color: Colors.white),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Close search',
              onPressed: () => setState(() {
                _searching = false;
                _query = '';
                _searchController.clear();
              }),
            )
          else ...[
            // Search and Filters are the two actions someone actually takes
            // on this screen, so they stay directly visible — plain white
            // "ghost" icons on the gradient rather than repeated solid white
            // circles, which read as heavy/repetitive in a row of four.
            IconButton(
              icon: const Icon(Icons.manage_search_rounded, color: Colors.white),
              tooltip: 'Search',
              onPressed: () => setState(() => _searching = true),
            ),
            IconButton(
              icon: Badge.count(
                count: _filter.activeCount,
                isLabelVisible: _filter.activeCount > 0,
                backgroundColor: Colors.white,
                textColor: AppClay.primary,
                child: const Icon(Icons.tune_rounded, color: Colors.white),
              ),
              tooltip: 'Filters',
              onPressed: _openFilters,
            ),
            // SMS Inbox stays directly visible (its unread count is
            // information worth surfacing at a glance); Trash alone goes in
            // the overflow menu since it's rarely used.
            Builder(
              builder: (context) {
                final pendingCount = ref.watch(smsPendingCountProvider);
                return IconButton(
                  icon: Badge.count(
                    count: pendingCount,
                    isLabelVisible: pendingCount > 0,
                    backgroundColor: Colors.white,
                    textColor: AppClay.primary,
                    child: const Icon(Icons.sms_outlined, color: Colors.white),
                  ),
                  tooltip: 'SMS Inbox',
                  onPressed: () => SmsInboxScreen.show(context),
                );
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'trash',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Trash'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (_) => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TransactionsTrashScreen()),
              ),
            ),
            const SizedBox(width: AppSizes.xs),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, 0),
            child: Row(
              children: [
                Expanded(
                  child: _DropdownField(
                    label: 'Date Range',
                    value: _dateRangeLabel(),
                    icon: Icons.calendar_today_outlined,
                    onTap: _pickDateRange,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: _DropdownField(
                    key: _sortFieldKey,
                    label: 'Sort By',
                    value: _sort.label,
                    icon: Icons.swap_vert_rounded,
                    onTap: () => _openSortMenu(context),
                  ),
                ),
              ],
            ),
          ),
          if (_filter.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.xs, AppSizes.lg, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _filter = TransactionFilter(accountId: widget.initialAccountId)),
                  icon: const Icon(Icons.close_rounded, size: AppSizes.iconSm),
                  label: Text('Clear ${_filter.activeCount} filter${_filter.activeCount == 1 ? '' : 's'}'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, 0),
            child: HistoryFilterChips(
              selected: _historyFilter,
              onChanged: (filter) => setState(() => _historyFilter = filter),
            ),
          ),
          Expanded(
            child: _historyFilter == HistoryFilter.all || _historyFilter == HistoryFilter.transactions
                ? _buildTransactionsBody(context, transactionsAsync, accountsById, categoriesById, peopleById, repository)
                : _buildUnifiedHistoryBody(context),
          ),
        ],
      ),
    );
  }

  String _dateRangeLabel() {
    final start = _filter.startDate;
    final end = _filter.endDate;
    if (start == null && end == null) return 'All Time';
    if (start != null && end != null) return '${start.shortDate} – ${end.shortDate}';
    return (start ?? end)!.shortDate;
  }

  Future<void> _openSortMenu(BuildContext context) async {
    final selected = await showAnchoredSortMenu<TransactionSort>(
      context: context,
      anchorKey: _sortFieldKey,
      selectedValue: _sort,
      options: [
        for (final sort in TransactionSort.values)
          SortMenuOption(
            value: sort,
            icon: _metricIconFor(sort),
            trailingIcon: _directionIconFor(sort),
            label: sort.label,
          ),
      ],
    );
    if (selected != null) setState(() => _sort = selected);
  }

  Widget _buildTransactionsBody(
    BuildContext context,
    AsyncValue<List<domain.Transaction>> transactionsAsync,
    Map<String, Account> accountsById,
    Map<String, Category> categoriesById,
    Map<String, Person> peopleById,
    TransactionRepository repository,
  ) {
    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Something went wrong: $error')),
      data: (transactions) {
        if (transactions.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions yet',
            subtitle: 'Add your first income or expense to start tracking your money.',
            action: FilledButton(
              onPressed: () => showAddEntryMenu(context),
              child: const Text('Add your first transaction'),
            ),
          );
        }

        final visible = _applyFilters(transactions, accountsById, categoriesById);

        if (visible.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matching transactions',
            subtitle: 'Try a different search term or clear your filters.',
          );
        }

        final sorted = _applySort(visible);
        final grouped = groupBy(sorted, (domain.Transaction t) => t.dateTime.dateOnly);
        final sortedDates = grouped.keys.toList()
          ..sort((a, b) => _sort == TransactionSort.dateAsc ? a.compareTo(b) : b.compareTo(a));

        // Flatten to header/row slots once per build so itemBuilder stays
        // O(1) and only visible rows get built (mirrors SearchScreen's
        // `_GroupedResults`), and precompute each header's net total here
        // instead of re-folding it inside the header widget every rebuild.
        final slots = <Object>[];
        for (final date in sortedDates) {
          slots.add((date: date, netTotal: grouped[date]!.fold(0.0, (sum, t) => sum + t.signedAmount)));
          slots.addAll(grouped[date]!);
        }

        return ListView.builder(
          // Bottom padding clears the shell's floating "+" button, same
          // convention as the Dashboard's scrollable body.
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.fabClearance),
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            if (slot is ({DateTime date, double netTotal})) {
              return TransactionDateGroupHeader(date: slot.date, netTotal: slot.netTotal);
            }
            final transaction = slot as domain.Transaction;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: Dismissible(
                key: ValueKey(transaction.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmAndDelete(repository, transaction),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                child: TransactionTile(
                  transaction: transaction,
                  category: categoriesById[transaction.categoryId],
                  account: accountsById[transaction.accountId],
                  linkedPersonName: peopleById[transaction.linkedPersonId]?.name,
                  onTap: () => context.push('${AppRoutes.transactions}/${transaction.id}'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnifiedHistoryBody(BuildContext context) {
    final entries = ref.watch(historyEntriesProvider).where(_historyFilter.matches).toList();
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? entries
        : entries
            .where((e) => e.title.toLowerCase().contains(query) || e.subtitle.toLowerCase().contains(query))
            .toList();

    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No ${_historyFilter.label.toLowerCase()} yet',
        subtitle: 'Activity in this category will show up here once you add some.',
      );
    }

    final grouped = groupBy(visible, (entry) => entry.date.dateOnly);
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    // Flatten to header/row slots once per build so itemBuilder stays O(1)
    // and only visible rows get built, and precompute each header's net
    // total here instead of re-folding it inside the header widget.
    final slots = <Object>[];
    for (final date in sortedDates) {
      slots.add((
        date: date,
        netTotal: grouped[date]!.fold(0.0, (sum, e) => sum + (e.isCredit ? e.amount : -e.amount)),
      ));
      slots.addAll(grouped[date]!);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSizes.lg),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        if (slot is ({DateTime date, double netTotal})) {
          return TransactionDateGroupHeader(date: slot.date, netTotal: slot.netTotal);
        }
        final entry = slot as HistoryEntry;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.sm),
          child: HistoryTile(
            entry: entry,
            onTap: entry.routePath == null ? null : () => context.push(entry.routePath!),
          ),
        );
      },
    );
  }

  /// Swipe-to-delete's `confirmDismiss`: asks Trash-vs-Permanent, then
  /// performs the chosen delete itself (rather than in `onDismissed`) so a
  /// cancelled/permanent choice can each report the right dismiss result.
  Future<bool> _confirmAndDelete(TransactionRepository repository, domain.Transaction transaction) async {
    final choice = await confirmDeleteWithPermanentOption(context, entityName: 'Transaction');
    // A transaction that's "owed" to a linked Person is really the
    // account-balance effect of an Expense (see `AddExpenseScreen`'s owed
    // toggle / `ExpenseRepository.assignToPerson`) — deleting it here must
    // cascade through the same repository that created it, so the ledger
    // entry and any tracking schedule/installments go with it, exactly like
    // `PersonStatementScreen`'s own delete already does. A plain (or
    // reference-only) transaction has no Expense at all and falls through to
    // the ordinary transaction-only delete unchanged.
    final expense = ref.read(expenseForTransactionProvider(transaction.id));
    switch (choice) {
      case DeleteChoice.cancel:
        return false;
      case DeleteChoice.trash:
        return expense != null
            ? await _deleteExpenseWithUndo(expense, transaction)
            : await _softDeleteWithUndo(repository, transaction);
      case DeleteChoice.permanent:
        try {
          if (expense != null) {
            // deleteExpense already reverses the account balance (via
            // TransactionRepository.softDeleteTransaction internally) before
            // soft-deleting everything — permanent delete just needs the final
            // hard-delete step afterward, same two-step shape as the plain
            // transaction branch below.
            await ref.read(expenseRepositoryProvider).deleteExpense(expense);
            await repository.permanentlyDeleteTransaction(transaction);
          } else {
            // permanentlyDeleteTransaction only removes the document — it assumes
            // the balance was already reversed by an earlier soft-delete. Since
            // this transaction is still active, reverse its balance effect first.
            await repository.softDeleteTransaction(transaction);
            await repository.permanentlyDeleteTransaction(transaction);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not delete transaction: $e')),
            );
          }
          return false;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction permanently deleted')),
          );
        }
        return true;
    }
  }

  Future<bool> _softDeleteWithUndo(TransactionRepository repository, domain.Transaction transaction) async {
    try {
      await repository.softDeleteTransaction(transaction);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete transaction: $e')),
        );
      }
      return false;
    }
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transaction moved to trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.restoreTransaction(transaction),
        ),
      ),
    );
    return true;
  }

  /// Cascading soft-delete for a transaction that's the account-balance
  /// effect of an [Expense] — reuses [ExpenseRepository.deleteExpense]
  /// wholesale rather than re-implementing its reversal logic. Undo reuses
  /// the matching [ExpenseRepository.restoreExpense] cascade, so a
  /// snackbar-undone "owed" expense comes back owed — ledger entry,
  /// schedule/installments and all — instead of reverting to a plain
  /// transaction.
  Future<bool> _deleteExpenseWithUndo(Expense expense, domain.Transaction transaction) async {
    final expenseRepository = ref.read(expenseRepositoryProvider);
    try {
      await expenseRepository.deleteExpense(expense);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete expense: $e')),
        );
      }
      return false;
    }
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Expense moved to trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => expenseRepository.restoreExpense(expense),
        ),
      ),
    );
    return true;
  }

  List<domain.Transaction> _applyFilters(
    List<domain.Transaction> transactions,
    Map<String, Account> accountsById,
    Map<String, Category> categoriesById,
  ) {
    final query = _query.trim().toLowerCase();

    return transactions.where((t) {
      if (!_filter.includeExcluded && t.excludeFromCalculations) return false;
      if (_filter.type != null && t.type != _filter.type) return false;
      if (_filter.accountId != null && t.accountId != _filter.accountId) return false;
      if (_filter.categoryId != null && t.categoryId != _filter.categoryId) return false;
      final filterDate = _filter.filterByAccountingMonth ? t.effectiveMonth : t.dateTime;
      if (_filter.startDate != null && filterDate.isBefore(_filter.startDate!)) return false;
      if (_filter.endDate != null && filterDate.isAfter(_filter.endDate!)) return false;

      if (query.isEmpty) return true;
      final categoryName = categoriesById[t.categoryId]?.name ?? '';
      final accountName = accountsById[t.accountId]?.name ?? '';
      return t.notes.toLowerCase().contains(query) ||
          categoryName.toLowerCase().contains(query) ||
          accountName.toLowerCase().contains(query);
    }).toList();
  }

  List<domain.Transaction> _applySort(List<domain.Transaction> transactions) {
    final sorted = [...transactions];
    switch (_sort) {
      case TransactionSort.dateDesc:
        sorted.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      case TransactionSort.dateAsc:
        sorted.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      case TransactionSort.amountDesc:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
      case TransactionSort.amountAsc:
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return sorted;
  }
}

/// The metric icon shown on a [TransactionSort] option's icon chip in the
/// "Sort By" sheet — date sorts get a calendar, amount sorts get ₹.
IconData _metricIconFor(TransactionSort sort) {
  switch (sort) {
    case TransactionSort.dateDesc:
    case TransactionSort.dateAsc:
      return Icons.calendar_month_outlined;
    case TransactionSort.amountDesc:
    case TransactionSort.amountAsc:
      return Icons.currency_rupee_rounded;
  }
}

/// The small up/down direction badge drawn on the corner of that icon chip.
IconData _directionIconFor(TransactionSort sort) {
  switch (sort) {
    case TransactionSort.dateDesc:
    case TransactionSort.amountDesc:
      return Icons.arrow_downward_rounded;
    case TransactionSort.dateAsc:
    case TransactionSort.amountAsc:
      return Icons.arrow_upward_rounded;
  }
}

/// A labeled, tappable field styled like a dropdown — used for the History
/// screen's "Date Range" / "Sort By" row. Opens whatever picker [onTap]
/// wires up (a sheet, a filter dialog, …) rather than being a real
/// [DropdownButton], since the underlying choices come from different
/// pickers depending on the field.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A soft floating well rather than a bordered box — matches the
    // ClayCard-style surfaces the rest of this screen now uses instead of
    // a flat Material outline.
    return Container(
      decoration: BoxDecoration(color: AppClay.card(context), boxShadow: AppClay.nested(context)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(icon, size: AppSizes.iconSm, color: colors.onSurface.withValues(alpha: 0.7)),
                    const SizedBox(width: AppSizes.xs),
                    Expanded(
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, size: AppSizes.iconSm, color: colors.onSurface.withValues(alpha: 0.5)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
