import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../expense/presentation/widgets/add_expense_chooser.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/ledger_entry_type.dart';
import '../../domain/person.dart';
import '../../domain/person_timeline_entry.dart';
import '../providers/people_providers.dart';
import '../providers/person_expense_stats_provider.dart';
import '../providers/person_statement_grouping_providers.dart';
import '../providers/person_timeline_providers.dart';
import '../widgets/adjust_balance_sheet.dart';
import '../widgets/ledger_entry_form_sheet.dart';
import '../widgets/person_expense_stats_card.dart';
import '../widgets/person_form_sheet.dart';
import '../widgets/person_pending_breakdown.dart';
import '../widgets/person_statement_groups_card.dart';
import '../widgets/person_statement_header.dart';
import '../widgets/request_payment.dart';
import '../widgets/settle_up_sheet.dart';
import '../widgets/share_statement.dart';
import 'person_expense_detail_screen.dart';
import 'person_ledger_trash_screen.dart';

/// Which view of the Contact Ledger is showing (Figma frame 1's tab bar):
/// the expense/lending history, an aggregated summary, or the payments this
/// person has made. History/Payments split on [PersonTimelineEntry.isSettlement].
enum _LedgerTab { history, summary, payments }

/// One person's Contact Ledger (Figma frame 1) — a reconciliation stat card,
/// a primary "Add Expense" CTA, and a History/Summary/Payments tab set over
/// the person's full timeline (expenses, lending, corrections, loans),
/// month-grouped and styled as cards. Tapping an expense row opens the
/// dedicated [PersonExpenseDetailScreen]. Secondary actions (record payment,
/// reminder, search, corrections, edit, share, trash, settle all) live in the
/// AppBar overflow so the screen reads as cleanly as the mockup.
class PersonStatementScreen extends ConsumerStatefulWidget {
  const PersonStatementScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<PersonStatementScreen> createState() => _PersonStatementScreenState();
}

class _PersonStatementScreenState extends ConsumerState<PersonStatementScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  DateTimeRange? _dateRange;
  _LedgerTab _tab = _LedgerTab.history;
  final _dismissedEntryIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  /// The entries visible in the current tab — History/Payments split on
  /// settlement, both narrowed by the active search query and date range.
  List<PersonTimelineEntry> _visibleFor(_LedgerTab tab, List<PersonTimelineEntry> entries) {
    final query = _query.trim().toLowerCase();
    return entries.where((e) {
      if (e.isSettlement != (tab == _LedgerTab.payments)) return false;
      if (query.isNotEmpty && !e.note.toLowerCase().contains(query) && !e.title.toLowerCase().contains(query)) {
        return false;
      }
      if (_dateRange != null && (e.date.isBefore(_dateRange!.start) || e.date.isAfter(_dateRange!.end))) return false;
      if (_dismissedEntryIds.contains(e.id)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleStreamProvider);
    final timeline = ref.watch(personTimelineProvider(widget.personId));
    final ledgerEntries = ref.watch(ledgerStreamProvider(widget.personId)).value ?? const [];
    final ledgerEntryById = {for (final e in ledgerEntries) e.id: e};

    final person = peopleAsync.value?.where((p) => p.id == widget.personId).firstOrNull;
    // Oldest-first, matching the mockup's within-month ordering.
    final sortedAll = [...timeline]..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search…', border: InputBorder.none),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(person?.name ?? 'Statement'),
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close search',
              onPressed: () => setState(() {
                _searching = false;
                _query = '';
                _searchController.clear();
              }),
            )
          else if (person != null)
            _OverflowMenu(person: person, entries: sortedAll, onAction: _handleMenuAction),
        ],
      ),
      floatingActionButton: person == null
          ? null
          : FloatingActionButton(
              heroTag: 'person_statement_fab',
              onPressed: () => LedgerEntryFormSheet.show(context, person),
              child: const Icon(Icons.add),
            ),
      body: person == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                PersonExpenseStatsCard(stats: ref.watch(personExpenseStatsProvider(widget.personId))),
                const SizedBox(height: AppSizes.lg),
                SegmentedButton<_LedgerTab>(
                  segments: const [
                    ButtonSegment(value: _LedgerTab.history, label: Text('History')),
                    ButtonSegment(value: _LedgerTab.summary, label: Text('Summary')),
                    ButtonSegment(value: _LedgerTab.payments, label: Text('Payments')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (selection) => setState(() => _tab = selection.first),
                ),
                const SizedBox(height: AppSizes.lg),
                if (_tab == _LedgerTab.summary)
                  _SummaryTab(person: person, entries: sortedAll, personId: widget.personId)
                else
                  ..._historyOrPayments(context, person, sortedAll, ledgerEntryById),
              ],
            ),
    );
  }

  List<Widget> _historyOrPayments(
    BuildContext context,
    Person person,
    List<PersonTimelineEntry> sortedAll,
    Map<String, LedgerEntry> ledgerEntryById,
  ) {
    final visible = _visibleFor(_tab, sortedAll);
    final isPayments = _tab == _LedgerTab.payments;

    return [
      if (_tab == _LedgerTab.history) ...[
        FilledButton.icon(
          onPressed: () => AddExpenseChooser.show(context, forPerson: person),
          icon: const Icon(Icons.add),
          label: const Text('Add Expense'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: AppSizes.lg),
      ],
      if (visible.isEmpty)
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: isPayments ? 'No payments yet' : 'No history yet',
          subtitle: isPayments
              ? 'Payments that clear this balance will show up here.'
              : 'Add an expense, or record money given or borrowed, to build the history.',
        )
      else
        ..._monthGrouped(context, person, visible, ledgerEntryById),
      if (_tab == _LedgerTab.history && visible.isNotEmpty) ...[
        const SizedBox(height: AppSizes.md),
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: AppSizes.iconSm, color: context.colors.primary),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  'Tap on any expense to view details, edit, add payment or split.',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  /// Groups [visible] (already oldest-first) by month, with a month header
  /// per group followed by the frame-1 cards.
  List<Widget> _monthGrouped(
    BuildContext context,
    Person person,
    List<PersonTimelineEntry> visible,
    Map<String, LedgerEntry> ledgerEntryById,
  ) {
    final widgets = <Widget>[];
    String? currentMonth;
    for (final entry in visible) {
      final month = entry.date.monthYear;
      if (month != currentMonth) {
        currentMonth = month;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: AppSizes.sm, bottom: AppSizes.sm),
          child: Text(month, style: context.textTheme.titleSmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.sm),
        child: _buildTile(context, person, entry, ledgerEntryById),
      ));
    }
    return widgets;
  }

  Widget _buildTile(
    BuildContext context,
    Person person,
    PersonTimelineEntry entry,
    Map<String, LedgerEntry> ledgerEntryById,
  ) {
    final transactionRef = _transactionRefFor(entry, ledgerEntryById);
    final tile = _ContactLedgerTile(
      entry: entry,
      onTap: transactionRef == null
          ? null
          : () => PersonExpenseDetailScreen.open(context, transactionId: transactionRef),
    );

    // Loan-derived entries have no editable ledger document, so they can't be
    // swipe-deleted; everything else keeps the swipe-to-trash gesture.
    final ledgerEntry = ledgerEntryById[entry.id];
    if (ledgerEntry == null) return tile;

    final ledgerRepository = ref.read(ledgerRepositoryProvider(widget.personId));
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDelete(context, entityName: transactionRef == null ? 'Entry' : 'Expense'),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        decoration: BoxDecoration(
          color: context.colors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.colors.error),
      ),
      onDismissed: (_) async {
        setState(() => _dismissedEntryIds.add(entry.id));
        if (transactionRef != null) {
          // Expense-linked entry: cascade-delete the whole expense (transaction,
          // schedule/installments, every linked ledger entry across all
          // participants) via ExpenseRepository.deleteExpense, otherwise the
          // Transaction/Expense docs stay live and keep counting toward
          // Dashboard/report totals and the person's cached balance.
          final expenses = await ref.read(expenseRepositoryProvider).getAll();
          final expense = expenses.firstWhereOrNull((e) => e.transactionId == transactionRef);
          if (expense != null) {
            await ref.read(expenseRepositoryProvider).deleteExpense(expense);
          } else {
            await ledgerRepository.softDeleteEntry(person, ledgerEntry);
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense deleted')));
          return;
        }
        await ledgerRepository.softDeleteEntry(person, ledgerEntry);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Entry moved to trash'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                ledgerRepository.restoreEntry(person, ledgerEntry);
                setState(() => _dismissedEntryIds.remove(entry.id));
              },
            ),
          ),
        );
      },
      child: tile,
    );
  }

  /// The linked `Expense.transactionId` behind an expense/assigned-expense
  /// timeline entry (via its `LedgerEntry.transactionRef`), or null for a
  /// plain lending/adjustment/loan entry that has no expense detail to open.
  String? _transactionRefFor(PersonTimelineEntry entry, Map<String, LedgerEntry> ledgerEntryById) {
    final isExpenseLinked =
        entry.category == PersonTimelineCategory.splitExpense || entry.category == PersonTimelineCategory.assignedExpense;
    if (!isExpenseLinked) return null;
    return ledgerEntryById[entry.id]?.transactionRef;
  }

  void _handleMenuAction(_MenuAction action, Person person, List<PersonTimelineEntry> entries) {
    switch (action) {
      case _MenuAction.recordPayment:
        SettleUpSheet.show(context, person);
      case _MenuAction.request:
        RequestPayment.send(person);
      case _MenuAction.search:
        setState(() => _searching = true);
      case _MenuAction.dateFilter:
        _pickDateRange();
      case _MenuAction.correctBalance:
        AdjustBalanceSheet.show(context, person);
      case _MenuAction.share:
        ShareStatement.share(context, person, entries);
      case _MenuAction.editPerson:
        PersonFormSheet.show(context, person: person);
      case _MenuAction.trash:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PersonLedgerTrashScreen(personId: widget.personId)),
        );
      case _MenuAction.settleAll:
        _confirmSettleAll(context, ref, person);
    }
  }

  /// One-tap "clear everything owed" — confirms, then records the whole
  /// pending balance as paid in a single [LedgerRepository.addEntry] call.
  Future<void> _confirmSettleAll(BuildContext context, WidgetRef ref, Person person) async {
    if (person.currentBalance == 0) return;
    final amount = CurrencyFormatter.instance.format(person.currentBalance.abs());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Settle All?'),
        content: Text(
          person.isCreditor
              ? 'Mark $amount from ${person.name} as fully paid? This clears their whole pending balance.'
              : 'Mark $amount to ${person.name} as fully paid? This clears your whole pending balance.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Settle All')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final repository = ref.read(ledgerRepositoryProvider(person.id));
      await repository.addEntry(
        person,
        type: person.isCreditor ? LedgerEntryType.receivedBack : LedgerEntryType.repaid,
        amount: person.currentBalance.abs(),
        date: DateTime.now(),
        note: 'Settled all',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${person.name}\'s balance is settled')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not settle: $e')));
      }
    }
  }
}

/// The aggregated "Summary" tab — the person's header stats, the pending
/// breakdown, and the credit-card statement grouping, all kept from the
/// pre-redesign screen so nothing analytical is lost.
class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.person, required this.entries, required this.personId});

  final Person person;
  final List<PersonTimelineEntry> entries;
  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        PersonStatementHeader(person: person, entries: entries),
        const SizedBox(height: AppSizes.lg),
        PersonPendingBreakdown(entries: entries),
        const SizedBox(height: AppSizes.lg),
        PersonStatementGroupsCard(groups: ref.watch(personStatementGroupsProvider(personId))),
      ],
    );
  }
}

enum _MenuAction { recordPayment, request, search, dateFilter, correctBalance, share, editPerson, trash, settleAll }

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.person, required this.entries, required this.onAction});

  final Person person;
  final List<PersonTimelineEntry> entries;
  final void Function(_MenuAction, Person, List<PersonTimelineEntry>) onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More',
      onSelected: (action) => onAction(action, person, entries),
      itemBuilder: (context) => [
        const PopupMenuItem(value: _MenuAction.recordPayment, child: _MenuTile(icon: Icons.swap_horiz_rounded, label: 'Record Payment')),
        const PopupMenuItem(value: _MenuAction.request, child: _MenuTile(icon: Icons.chat_bubble_outline_rounded, label: 'Send Reminder')),
        const PopupMenuItem(value: _MenuAction.search, child: _MenuTile(icon: Icons.search_rounded, label: 'Search')),
        const PopupMenuItem(value: _MenuAction.dateFilter, child: _MenuTile(icon: Icons.date_range_outlined, label: 'Date Filter')),
        const PopupMenuItem(value: _MenuAction.correctBalance, child: _MenuTile(icon: Icons.tune_rounded, label: 'Correct Balance')),
        const PopupMenuItem(value: _MenuAction.share, child: _MenuTile(icon: Icons.share_outlined, label: 'Share Statement')),
        const PopupMenuItem(value: _MenuAction.editPerson, child: _MenuTile(icon: Icons.edit_outlined, label: 'Edit Person')),
        const PopupMenuItem(value: _MenuAction.trash, child: _MenuTile(icon: Icons.delete_outline_rounded, label: 'Trash')),
        if (person.currentBalance != 0)
          const PopupMenuItem(value: _MenuAction.settleAll, child: _MenuTile(icon: Icons.done_all_rounded, label: 'Settle All')),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconSm),
        const SizedBox(width: AppSizes.md),
        Text(label),
      ],
    );
  }
}

/// One row in the Contact Ledger's month-grouped list (Figma frame 1's card):
/// a tinted category/type icon, the expense description, its date and money
/// direction, the signed amount, and — for expense entries — a status pill.
class _ContactLedgerTile extends StatelessWidget {
  const _ContactLedgerTile({required this.entry, required this.onTap});

  final PersonTimelineEntry entry;
  final VoidCallback? onTap;

  static const _splitSettlementPrefix = 'Split settlement:';
  static const _splitGivenPrefix = 'Split:';

  String get _title {
    final note = entry.note;
    if (note.startsWith(_splitSettlementPrefix)) return note.substring(_splitSettlementPrefix.length).trim();
    if (note.startsWith(_splitGivenPrefix)) return note.substring(_splitGivenPrefix.length).trim();
    return note.isNotEmpty ? note : entry.title;
  }

  @override
  Widget build(BuildContext context) {
    final signed = entry.signedAmount;
    final positive = signed >= 0;
    final amountColor = entry.color;
    final directionLabel = signed == 0 ? null : (positive ? 'To Receive' : 'To Pay');
    final directionColor = positive ? AppColors.success : AppColors.error;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: amountColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
                child: Icon(entry.icon, color: amountColor, size: AppSizes.iconSm),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_title, style: context.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Text(
                          CurrencyFormatter.instance.format(signed.abs()),
                          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: amountColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          directionLabel == null ? entry.date.fullDate : '${entry.date.fullDate} · $directionLabel',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: directionLabel == null ? context.colors.onSurface.withValues(alpha: 0.6) : directionColor,
                          ),
                        ),
                        const Spacer(),
                        if (entry.status != null) _StatusPill(status: entry.status!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The frame-1 status pill wording (Settled ✓ / Pending / Partial / Overdue)
/// for a person-timeline entry, mapped from [PersonTimelineStatus].
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final PersonTimelineStatus status;

  (String, Color) get _display {
    switch (status) {
      case PersonTimelineStatus.completed:
        return ('Settled ✓', AppColors.success);
      case PersonTimelineStatus.pending:
        return ('Pending', AppColors.pending);
      case PersonTimelineStatus.partial:
        return ('Partial', AppColors.warning);
      case PersonTimelineStatus.overdue:
        return ('Overdue', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _display;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
      child: Text(label, style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
