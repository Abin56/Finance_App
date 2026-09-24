import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../expense/presentation/widgets/add_expense_chooser.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/person.dart';
import '../../domain/person_timeline_entry.dart';
import '../providers/people_providers.dart';
import '../providers/person_expense_stats_provider.dart';
import '../providers/person_pending_participants_providers.dart';
import '../providers/person_statement_grouping_providers.dart';
import '../providers/person_timeline_providers.dart';
import '../widgets/adjust_balance_sheet.dart';
import '../widgets/ledger_entry_form_sheet.dart';
import '../widgets/person_cycle_summary_card.dart';
import '../widgets/person_expense_stats_card.dart';
import '../widgets/person_form_sheet.dart';
import '../widgets/person_loan_ledger_summary_card.dart';
import '../widgets/person_loans_summary_card.dart';
import '../widgets/person_pending_breakdown.dart';
import '../widgets/person_statement_groups_card.dart';
import '../widgets/person_statement_header.dart';
import '../widgets/request_payment.dart';
import '../widgets/settle_up_sheet.dart';
import '../widgets/share_statement.dart';
import 'person_expense_detail_screen.dart';
import 'person_ledger_trash_screen.dart';
import 'statement_pdf_preview_screen.dart';

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
  ConsumerState<PersonStatementScreen> createState() =>
      _PersonStatementScreenState();
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
  List<PersonTimelineEntry> _visibleFor(
    _LedgerTab tab,
    List<PersonTimelineEntry> entries,
  ) {
    final query = _query.trim().toLowerCase();
    return entries.where((e) {
      if (e.isSettlement != (tab == _LedgerTab.payments)) return false;
      if (query.isNotEmpty &&
          !e.note.toLowerCase().contains(query) &&
          !e.title.toLowerCase().contains(query)) {
        return false;
      }
      if (_dateRange != null) {
        // `_dateRange!.end` is midnight on the selected end date (from
        // `showDateRangePicker`), but loan-payment/referenced-transaction
        // entries carry a real time-of-day — comparing against end-of-day
        // instead of midnight keeps "today" actually including today.
        final endOfRangeDay = DateTime(
          _dateRange!.end.year,
          _dateRange!.end.month,
          _dateRange!.end.day,
          23,
          59,
          59,
        );
        if (e.date.isBefore(_dateRange!.start) ||
            e.date.isAfter(endOfRangeDay)) {
          return false;
        }
      }
      if (_dismissedEntryIds.contains(e.id)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleStreamProvider);
    final timeline = ref.watch(personTimelineProvider(widget.personId));
    final cycleView = ref.watch(personCycleViewProvider(widget.personId));
    final ledgerEntries =
        ref.watch(ledgerStreamProvider(widget.personId)).value ?? const [];
    final ledgerEntryById = {for (final e in ledgerEntries) e.id: e};

    final person = peopleAsync.value
        ?.where((p) => p.id == widget.personId)
        .firstOrNull;
    // Oldest-first, matching the mockup's within-month ordering.
    final sortedAll = [...timeline]..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search…',
                  border: InputBorder.none,
                ),
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
          else if (person != null) ...[
            if (_tab == _LedgerTab.history)
              Padding(
                padding: const EdgeInsets.only(right: AppSizes.xs),
                child: Center(
                  child: Material(
                    color: context.colors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () =>
                          AddExpenseChooser.show(context, forPerson: person),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md,
                          vertical: AppSizes.sm,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: AppSizes.iconSm,
                              color: context.colors.onPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add',
                              style: context.textTheme.labelLarge?.copyWith(
                                color: context.colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            _OverflowMenu(
              person: person,
              entries: sortedAll,
              onAction: _handleMenuAction,
            ),
          ],
        ],
      ),
      floatingActionButton: person == null
          ? null
          : FloatingActionButton(
              heroTag: 'person_statement_fab',
              onPressed: () => LedgerEntryFormSheet.show(context, person),
              child: const Icon(Icons.add),
            ),
      body: SafeArea(
        child: person == null
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.lg,
                      AppSizes.lg,
                      AppSizes.lg,
                      _tab == _LedgerTab.summary ? AppSizes.lg : 0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        PersonExpenseStatsCard(
                          stats: ref.watch(
                            personExpenseStatsProvider(widget.personId),
                          ),
                        ),
                        const SizedBox(height: AppSizes.lg),
                        SegmentedButton<_LedgerTab>(
                          segments: const [
                            ButtonSegment(
                              value: _LedgerTab.history,
                              label: Text('History'),
                            ),
                            ButtonSegment(
                              value: _LedgerTab.summary,
                              label: Text('Summary'),
                            ),
                            ButtonSegment(
                              value: _LedgerTab.payments,
                              label: Text('Payments'),
                            ),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (selection) =>
                              setState(() => _tab = selection.first),
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: context.colors.primary,
                            selectedForegroundColor: context.colors.onPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSizes.lg),
                        if (_tab == _LedgerTab.summary)
                          _SummaryTab(
                            person: person,
                            entries: sortedAll,
                            personId: widget.personId,
                          ),
                      ],
                    ),
                  ),
                  if (_tab != _LedgerTab.summary)
                    ..._historyOrPaymentsSlivers(
                      context,
                      person,
                      sortedAll,
                      ledgerEntryById,
                      cycleView,
                    ),
                ],
              ),
      ),
    );
  }

  List<Widget> _historyOrPaymentsSlivers(
    BuildContext context,
    Person person,
    List<PersonTimelineEntry> sortedAll,
    Map<String, LedgerEntry> ledgerEntryById,
    PersonCycleView cycleView,
  ) {
    final visible = _visibleFor(_tab, sortedAll);
    final isPayments = _tab == _LedgerTab.payments;

    if (visible.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          sliver: SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: isPayments ? 'No payments yet' : 'No history yet',
              subtitle: isPayments
                  ? 'Payments that clear this balance will show up here.'
                  : 'Add an expense, or record money given or borrowed, to build the history.',
            ),
          ),
        ),
      ];
    }

    // The Payments tab is entirely settlements (no `assignedExpense`/
    // `splitExpense` entry is ever a settlement itself, see
    // `PersonTimelineEntry.isSettlement`), so cycle sectioning — which only
    // ever applies to those two categories — never has anything to show
    // there; keep its existing flat month-grouped rendering unchanged.
    final slots = isPayments
        ? _monthGroupedSlots(visible)
        : _cycleSectionedSlots(visible, cycleView);

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        sliver: SliverToBoxAdapter(
          child: _buildTable(
            context,
            person,
            slots,
            ledgerEntryById,
            cycleView,
          ),
        ),
      ),
      if (_tab == _LedgerTab.history)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.md,
            AppSizes.lg,
            AppSizes.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: AppSizes.iconSm,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      'Tap on any expense to view details, edit, add payment or split.',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  /// The plain flat month-header/row slots, unchanged from before cycle
  /// sectioning existed — used for the Payments tab, which cycle sectioning
  /// never applies to (see [_historyOrPaymentsSlivers]).
  List<Object> _monthGroupedSlots(List<PersonTimelineEntry> entries) {
    final slots = <Object>[];
    String? currentMonth;
    for (final entry in entries) {
      final month = entry.date.monthYear;
      if (month != currentMonth) {
        currentMonth = month;
        slots.add(month);
      }
      slots.add(entry);
    }
    return slots;
  }

  /// History tab slots: a "Previous Cycle Pending" section (only when
  /// [PersonCycleView.previousCyclePending] is non-empty — fully settled
  /// previous-cycle entries simply have nothing to show there), followed by
  /// "Current Cycle" containing the carried-forward entries first, then
  /// every other visible entry (current-cycle expense-linked entries plus
  /// every uncycled running-balance entry — lending, settlements,
  /// adjustments, references — month-grouped exactly as before).
  List<Object> _cycleSectionedSlots(
    List<PersonTimelineEntry> visible,
    PersonCycleView cycleView,
  ) {
    final visibleIds = visible.map((e) => e.id).toSet();
    final previousPending = cycleView.previousCyclePending
        .where((e) => visibleIds.contains(e.id))
        .toList();
    final carriedForward = previousPending.toList();
    final carriedForwardIds = carriedForward.map((e) => e.id).toSet();
    final rest = visible
        .where((e) => !carriedForwardIds.contains(e.id))
        .toList();

    final slots = <Object>[];
    if (previousPending.isNotEmpty) {
      slots.add(const _CycleSectionHeader('Previous Cycle Pending'));
      slots.addAll(_monthGroupedSlots(previousPending));
    }
    slots.add(const _CycleSectionHeader('Current Cycle'));
    slots.addAll(_monthGroupedSlots([...carriedForward, ...rest]));
    return slots;
  }

  /// The People transaction table: one horizontally scrollable grid with a
  /// header row, section/cycle label rows, and one numbered row per entry.
  Widget _buildTable(
    BuildContext context,
    Person person,
    List<Object> slots,
    Map<String, LedgerEntry> ledgerEntryById,
    PersonCycleView cycleView,
  ) {
    var number = 0;
    final rows = <Widget>[const _TableHeaderRow()];
    for (final slot in slots) {
      if (slot is _CycleSectionHeader) {
        rows.add(_TableSectionRow(label: slot.label, emphasized: true));
      } else if (slot is String) {
        rows.add(_TableSectionRow(label: slot));
      } else {
        final entry = slot as PersonTimelineEntry;
        if (entry.isSectionHeader) {
          rows.add(_TableSectionRow(label: entry.title));
          continue;
        }
        number++;
        final transactionRef = _transactionRefFor(entry, ledgerEntryById);
        final ledgerEntry = ledgerEntryById[entry.id];
        rows.add(
          _LedgerTableRow(
            number: number,
            entry: entry,
            carriedForward: cycleView.carriedForwardIds.contains(entry.id),
            onTap: entry.category == PersonTimelineCategory.reference
                ? () => context.push('${AppRoutes.transactions}/${entry.id}')
                : transactionRef == null
                ? null
                : () => PersonExpenseDetailScreen.open(
                    context,
                    transactionId: transactionRef,
                  ),
            onDelete: ledgerEntry == null
                ? null
                : () => _deleteEntry(
                    context,
                    person,
                    entry,
                    ledgerEntry,
                    transactionRef,
                  ),
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _kTableWidth,
          child: Column(children: rows),
        ),
      ),
    );
  }

  /// Confirms, then deletes one ledger-backed row — cascading through the
  /// whole expense when the entry is expense-linked, otherwise moving just the
  /// ledger entry to trash with an Undo.
  Future<void> _deleteEntry(
    BuildContext context,
    Person person,
    PersonTimelineEntry entry,
    LedgerEntry ledgerEntry,
    String? transactionRef,
  ) async {
    final confirmed = await confirmDelete(
      context,
      entityName: transactionRef == null ? 'Entry' : 'Expense',
    );
    if (confirmed != true || !context.mounted) return;

    final ledgerRepository = ref.read(
      ledgerRepositoryProvider(widget.personId),
    );
    setState(() => _dismissedEntryIds.add(entry.id));
    if (transactionRef != null) {
      // Expense-linked entry: cascade-delete the whole expense (transaction,
      // schedule/installments, every linked ledger entry across all
      // participants) via ExpenseRepository.deleteExpense, otherwise the
      // Transaction/Expense docs stay live and keep counting toward
      // Dashboard/report totals and the person's cached balance.
      final expenses = await ref.read(expenseRepositoryProvider).getAll();
      final expense = expenses.firstWhereOrNull(
        (e) => e.transactionId == transactionRef,
      );
      if (expense != null) {
        await ref.read(expenseRepositoryProvider).deleteExpense(expense);
      } else {
        await ledgerRepository.softDeleteEntry(person, ledgerEntry);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expense deleted')));
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
  }

  /// The linked `Expense.transactionId` behind an expense/assigned-expense
  /// timeline entry (via its `LedgerEntry.transactionRef`), or null for a
  /// plain lending/adjustment/loan entry that has no expense detail to open.
  String? _transactionRefFor(
    PersonTimelineEntry entry,
    Map<String, LedgerEntry> ledgerEntryById,
  ) {
    final isExpenseLinked =
        entry.category == PersonTimelineCategory.splitExpense ||
        entry.category == PersonTimelineCategory.assignedExpense;
    if (!isExpenseLinked) return null;
    return ledgerEntryById[entry.id]?.transactionRef;
  }

  void _handleMenuAction(
    _MenuAction action,
    Person person,
    List<PersonTimelineEntry> entries,
  ) {
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
      case _MenuAction.exportPdf:
        _exportPdf(person, sortedAllFor: entries);
      case _MenuAction.editPerson:
        PersonFormSheet.show(context, person: person);
      case _MenuAction.trash:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PersonLedgerTrashScreen(personId: widget.personId),
          ),
        );
      case _MenuAction.settleAll:
        _confirmSettleAll(context, ref, person);
    }
  }

  /// Exports exactly what's currently visible on screen — the active tab's
  /// filtered rows (History/Payments honor search + date range; Summary
  /// exports the full timeline, matching what [_SummaryTab] itself displays,
  /// since its aggregates are never narrowed by search/date range either).
  void _exportPdf(
    Person person, {
    required List<PersonTimelineEntry> sortedAllFor,
  }) {
    final visible = _tab == _LedgerTab.summary
        ? sortedAllFor
        : _visibleFor(_tab, sortedAllFor);

    // Running balance is a chronological fold over the person's *entire*
    // ledger, not just the visible subset — so the balance carried into the
    // first visible row is `openingBalance` plus every earlier entry in the
    // full timeline, regardless of tab/search. Without this, a date-range
    // filter that excludes earlier history would make every running balance
    // shown in the PDF wrong.
    final openingBalanceForRange = visible.isEmpty
        ? person.openingBalance
        : person.openingBalance +
              sortedAllFor
                  .where((e) => e.date.isBefore(visible.first.date))
                  .fold(0.0, (sum, e) => sum + e.signedAmount);

    final currentUser = ref.read(authRepositoryProvider).currentUser;
    StatementPdfPreviewScreen.open(
      context,
      person: person,
      entries: visible,
      expenseStats: ref.read(personExpenseStatsProvider(widget.personId)),
      filterDescription: _filterDescription(),
      openingBalanceForRange: openingBalanceForRange,
      currentUserEmail: currentUser?.email,
      currentUserDisplayName: currentUser?.displayName,
    );
  }

  /// Human-readable summary of the active tab/search/date-range filter, e.g.
  /// "History · 1 Jan – 31 Jan 2026 · "fuel"" — shown on the PDF's
  /// Statement Info section so a reader never mistakes a filtered export
  /// for the person's full history. Empty when nothing is filtered.
  String _filterDescription() {
    if (_tab == _LedgerTab.summary) return '';
    final parts = <String>[
      _tab == _LedgerTab.payments ? 'Payments' : 'History',
    ];
    if (_dateRange != null) {
      parts.add('${_dateRange!.start.fullDate} – ${_dateRange!.end.fullDate}');
    }
    if (_query.trim().isNotEmpty) parts.add('"${_query.trim()}"');
    return parts.join(' · ');
  }

  /// One-tap "clear everything owed" — confirms, then fans the whole pending
  /// balance out across the person's outstanding installments oldest-first
  /// via [ExpenseRepository.settleAcrossPending], so every dollar produces a
  /// traceable settlement instead of one undifferentiated ledger entry.
  Future<void> _confirmSettleAll(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    if (person.currentBalance == 0) return;
    final amount = CurrencyFormatter.instance.format(
      person.currentBalance.abs(),
    );
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Settle All'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final pending =
          ref
              .read(personSplitParticipantsProvider(person.id))
              .where((p) => p.installment.remainingAmount > 0)
              .toList()
            ..sort(
              (a, b) => a.installment.dueDate.compareTo(b.installment.dueDate),
            );

      await ref
          .read(expenseRepositoryProvider)
          .settleAcrossPending(
            person: person,
            pending: pending,
            amount: person.currentBalance.abs(),
            date: DateTime.now(),
            installmentPaymentRepositoryFor: (scheduleId, installmentId) =>
                ref.read(
                  installmentPaymentRepositoryProvider((
                    scheduleId: scheduleId,
                    installmentId: installmentId,
                  )),
                ),
            note: 'Settled all',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${person.name}\'s balance is settled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not settle: $e')));
      }
    }
  }
}

/// The aggregated "Summary" tab — the person's header stats, the pending
/// breakdown, and the credit-card statement grouping, all kept from the
/// pre-redesign screen so nothing analytical is lost.
class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({
    required this.person,
    required this.entries,
    required this.personId,
  });

  final Person person;
  final List<PersonTimelineEntry> entries;
  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        PersonStatementHeader(person: person, entries: entries),
        const SizedBox(height: AppSizes.lg),
        PersonCycleSummaryCard(
          summary: ref.watch(personCycleSummaryProvider(personId)),
        ),
        const SizedBox(height: AppSizes.lg),
        PersonPendingBreakdown(entries: entries),
        const SizedBox(height: AppSizes.lg),
        PersonLoanLedgerSummaryCard(person: person),
        const SizedBox(height: AppSizes.lg),
        PersonLoansSummaryCard(person: person),
        const SizedBox(height: AppSizes.lg),
        PersonStatementGroupsCard(
          groups: ref.watch(personStatementGroupsProvider(personId)),
        ),
      ],
    );
  }
}

enum _MenuAction {
  recordPayment,
  request,
  search,
  dateFilter,
  correctBalance,
  share,
  exportPdf,
  editPerson,
  trash,
  settleAll,
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.person,
    required this.entries,
    required this.onAction,
  });

  final Person person;
  final List<PersonTimelineEntry> entries;
  final void Function(_MenuAction, Person, List<PersonTimelineEntry>) onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More',
      onSelected: (action) => onAction(action, person, entries),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _MenuAction.recordPayment,
          child: _MenuTile(
            icon: Icons.swap_horiz_rounded,
            label: 'Record Payment',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.request,
          child: _MenuTile(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Send Reminder',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.search,
          child: _MenuTile(icon: Icons.search_rounded, label: 'Search'),
        ),
        const PopupMenuItem(
          value: _MenuAction.dateFilter,
          child: _MenuTile(
            icon: Icons.date_range_outlined,
            label: 'Date Filter',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.correctBalance,
          child: _MenuTile(icon: Icons.tune_rounded, label: 'Correct Balance'),
        ),
        const PopupMenuItem(
          value: _MenuAction.share,
          child: _MenuTile(icon: Icons.notes_rounded, label: 'Share as Text'),
        ),
        const PopupMenuItem(
          value: _MenuAction.exportPdf,
          child: _MenuTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Export PDF',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.editPerson,
          child: _MenuTile(icon: Icons.edit_outlined, label: 'Edit Person'),
        ),
        const PopupMenuItem(
          value: _MenuAction.trash,
          child: _MenuTile(icon: Icons.delete_outline_rounded, label: 'Trash'),
        ),
        if (person.currentBalance != 0)
          const PopupMenuItem(
            value: _MenuAction.settleAll,
            child: _MenuTile(icon: Icons.done_all_rounded, label: 'Settle All'),
          ),
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

const double _kNoW = 48;
const double _kStatusW = 132;
const double _kDateW = 92;
const double _kDescW = 230;
const double _kAmountW = 120;
const double _kTypeW = 150;
const double _kActionW = 56;
const double _kTableWidth =
    _kNoW + _kStatusW + _kDateW + _kDescW + _kAmountW + _kTypeW + _kActionW;

/// Header row of the People transaction table (NO / STATUS / DATE / …).
class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: context.colors.onSurface.withValues(alpha: 0.6),
    );
    Widget cell(String t, double w, {TextAlign align = TextAlign.left}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
            child: Text(t, style: style, textAlign: align),
          ),
        );
    return Container(
      height: 40,
      color: context.colors.onSurface.withValues(alpha: 0.05),
      child: Row(
        children: [
          cell('NO', _kNoW),
          cell('STATUS', _kStatusW),
          cell('DATE', _kDateW),
          cell('DESCRIPTION', _kDescW),
          cell('AMOUNT', _kAmountW, align: TextAlign.right),
          cell('TYPE', _kTypeW),
          const SizedBox(width: _kActionW),
        ],
      ),
    );
  }
}

/// A full-width label row inside the table (month / cycle / loan headings).
class _TableSectionRow extends StatelessWidget {
  const _TableSectionRow({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kTableWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: emphasized
            ? context.colors.primary.withValues(alpha: 0.08)
            : null,
        border: Border(
          top: BorderSide(color: context.colors.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: emphasized
              ? context.colors.primary
              : context.colors.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// One numbered transaction row of the People table: NO, status, date,
/// description (+ subtitle), signed amount, type, and a delete action.
class _LedgerTableRow extends StatelessWidget {
  const _LedgerTableRow({
    required this.number,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.carriedForward = false,
  });

  final int number;
  final PersonTimelineEntry entry;
  final VoidCallback? onTap;

  /// Null for loan-derived entries, which have no editable ledger document.
  final VoidCallback? onDelete;
  final bool carriedForward;

  static const _splitSettlementPrefix = 'Split settlement:';
  static const _splitGivenPrefix = 'Split:';

  String get _title {
    final note = entry.note;
    if (note.startsWith(_splitSettlementPrefix)) {
      return note.substring(_splitSettlementPrefix.length).trim();
    }
    if (note.startsWith(_splitGivenPrefix)) {
      return note.substring(_splitGivenPrefix.length).trim();
    }
    return note.isNotEmpty ? note : entry.title;
  }

  bool get _hasPartialPayment {
    final total = entry.totalAmount;
    final paid = entry.paidAmount;
    return total != null && paid != null && paid > 0 && paid < total;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = colors.onSurface.withValues(alpha: 0.6);
    final signed = entry.signedAmount;
    final direction = signed == 0
        ? null
        : (signed >= 0 ? 'To Receive' : 'To Pay');

    Widget cell(double w, Widget child) => SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
        child: child,
      ),
    );

    final Widget status;
    if (carriedForward) {
      status = const _TableChip(label: 'Carried fwd', color: AppColors.warning);
    } else if (entry.category == PersonTimelineCategory.reference) {
      status = const _TableChip(label: 'Reference', color: AppColors.pending);
    } else if (entry.status != null) {
      status = _TableChip(
        label: entry.status!.label,
        color: entry.status!.color,
      );
    } else {
      status = Text('—', style: TextStyle(color: muted));
    }

    return Material(
      color: carriedForward
          ? AppColors.warning.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              cell(
                _kNoW,
                Text(
                  number.toString().padLeft(2, '0'),
                  style: context.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              cell(
                _kStatusW,
                Align(alignment: Alignment.centerLeft, child: status),
              ),
              cell(
                _kDateW,
                Text(entry.date.shortDate, style: context.textTheme.bodyMedium),
              ),
              cell(
                _kDescW,
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.otherParticipantNames.isNotEmpty ||
                        direction != null)
                      Text(
                        entry.otherParticipantNames.isNotEmpty
                            ? 'with ${entry.otherParticipantNames.join(', ')}'
                            : direction!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              cell(
                _kAmountW,
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.instance.format(
                        entry.remainingDisplayAmount.abs(),
                      ),
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: entry.color,
                      ),
                    ),
                    if (_hasPartialPayment)
                      Text(
                        'of ${CurrencyFormatter.instance.format(entry.totalAmount!.abs())}',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              cell(
                _kTypeW,
                Text(
                  entry.category.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              SizedBox(
                width: _kActionW,
                child: onDelete == null
                    ? null
                    : IconButton(
                        tooltip: 'Delete',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: AppSizes.iconSm,
                          color: colors.error,
                        ),
                        onPressed: onDelete,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableChip extends StatelessWidget {
  const _TableChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A cycle-section header within the History tab's list — "Previous Cycle
/// Pending" or "Current Cycle" — distinct from the plain month-header
/// strings the same slot list also carries (see `_cycleSectionedSlots`).
class _CycleSectionHeader {
  const _CycleSectionHeader(this.label);

  final String label;
}
