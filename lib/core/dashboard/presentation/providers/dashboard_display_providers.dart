import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/local_settings_service.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/cash_flow/domain/cash_flow_period.dart';
import '../../../../features/cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../../../features/categories/presentation/providers/category_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/people/presentation/providers/people_providers.dart';
import '../../../../features/people/presentation/providers/person_position_providers.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../domain/date_range_strategy.dart';
import 'upcoming_due_provider.dart';

// Display-only compositions for the Dashboard. Nothing here writes data or
// re-derives a figure a feature already owns: each provider rearranges
// already-final totals (Net Worth, liabilities, cash-flow lines, upcoming
// dues) into the shape a Dashboard section needs.

double _round2(double v) => (v * 100).round() / 100;

// ---------------------------------------------------------------------------
// Net Worth composition (Assets / Debt)
// ---------------------------------------------------------------------------

typedef NetWorthComposition = ({
  double assets,
  double debt,
  double loanDebt,
  double peopleDebt,
});

/// Net Worth split into what I own and what I owe, mirroring Web's
/// `netWorthComposition` (`lib/engines/loan-balance-sheet.ts`):
///  - debt = every liability once ([liabilityTotalsProvider]: card debt from
///    the card accounts' own balances + card-locked EMI + remaining loan/EMI
///    principal) + what I owe people directly (negative direct balances);
///  - assets = Net Worth + debt, so `assets − debt == netWorth` exactly.
/// Flutter has no "advance held for people" figure, so unlike Web there is
/// no third "Held for people" line rather than an invented zero.
final netWorthCompositionProvider = Provider<NetWorthComposition>((ref) {
  final netWorth = ref.watch(netWorthWithLoansProvider);
  final liabilities = ref.watch(liabilityTotalsProvider);
  final people = ref.watch(peopleStreamProvider).value ?? const [];
  var peopleDebt = 0.0;
  for (final p in people) {
    final direct = ref.watch(personPositionProvider(p.id)).directBalance;
    if (direct < 0) peopleDebt -= direct;
  }
  final debt = _round2(liabilities.total + peopleDebt);
  return (
    assets: _round2(netWorth + debt),
    debt: debt,
    loanDebt: _round2(liabilities.loanDebt),
    peopleDebt: _round2(peopleDebt),
  );
});

// ---------------------------------------------------------------------------
// Net Worth 7-day trend
// ---------------------------------------------------------------------------

enum NetWorthTrendStatus { loading, available, unavailable }

@immutable
class NetWorthTrend {
  const NetWorthTrend._(this.status, this.values);

  const NetWorthTrend.loading() : this._(NetWorthTrendStatus.loading, null);
  const NetWorthTrend.unavailable()
    : this._(NetWorthTrendStatus.unavailable, null);
  const NetWorthTrend.available(List<double> values)
    : this._(NetWorthTrendStatus.available, values);

  final NetWorthTrendStatus status;

  /// Net Worth at the end of each of the last 7 days, oldest first; the last
  /// value is today's headline figure. Only set when [status] is available.
  final List<double>? values;

  bool get isFlat =>
      values != null && values!.every((v) => (v - values!.first).abs() < 0.5);
}

/// The real Net Worth history for the last 7 days — not a cumulative cash
/// flow (the old sparkline summed income − expense from zero, which is not
/// Net Worth at all). Mirrors Web's corrected rule (WFI-P3-05,
/// `use-dashboard-data.ts`): anchor on today's Net Worth and walk back every
/// later transaction that changes it; transfers are Net-Worth-neutral and
/// skipped.
///
/// Walking back is only exact when every Net Worth change in the window came
/// from a plain account transaction. Anything else — a loan/EMI payment
/// (interest vs principal split), a People ledger movement or person-linked /
/// split expense (receivable created alongside the spend), or an account,
/// loan, EMI or person created in the window (an opening figure with no
/// transaction) — makes the history unknowable from records alone, so the
/// trend reports [NetWorthTrendStatus.unavailable] instead of drawing a
/// guessed line.
final netWorthTrendProvider = Provider<NetWorthTrend>((ref) {
  final transactions = ref.watch(transactionsStreamProvider);
  final accounts = ref.watch(accountsStreamProvider);
  final loans = ref.watch(loansStreamProvider);
  final emis = ref.watch(emisStreamProvider);
  final people = ref.watch(peopleStreamProvider);
  final expenses = ref.watch(expensesStreamProvider);
  if (!transactions.hasValue ||
      !accounts.hasValue ||
      !loans.hasValue ||
      !emis.hasValue ||
      !people.hasValue ||
      !expenses.hasValue) {
    return const NetWorthTrend.loading();
  }

  final today = DateTime.now().dateOnly;
  // Point 0 is the end of (today − 6); everything from the next midnight on
  // has to be replayed.
  final windowStart = today.subtract(const Duration(days: 5));
  bool inWindow(DateTime d) => !d.isBefore(windowStart);

  final created = [
    for (final a in accounts.requireValue) a.createdAt,
    for (final l in loans.requireValue) l.createdAt,
    for (final e in emis.requireValue) e.createdAt,
    for (final p in people.requireValue) p.createdAt,
  ];
  if (created.any(inWindow)) return const NetWorthTrend.unavailable();

  for (final p in people.requireValue) {
    final ledger = ref.watch(ledgerStreamProvider(p.id));
    if (!ledger.hasValue) return const NetWorthTrend.loading();
    if (ledger.requireValue.any(
      (e) => inWindow(e.date) || inWindow(e.createdAt),
    )) {
      return const NetWorthTrend.unavailable();
    }
  }

  final splitTransactionIds = {
    for (final e in expenses.requireValue)
      if (e.deletedAt == null) e.transactionId,
  };
  final replay = <({DateTime at, double effect})>[];
  for (final t in transactions.requireValue) {
    if (!inWindow(t.dateTime)) continue;
    if (t.isTransfer) continue; // two own-account legs cancel out
    final effect = t.balanceEffect;
    if (effect == 0) continue;
    if (t.loanId != null ||
        t.emiId != null ||
        t.isPersonLedgerMovement ||
        t.linkedPersonId != null ||
        splitTransactionIds.contains(t.id)) {
      return const NetWorthTrend.unavailable();
    }
    replay.add((at: t.dateTime, effect: effect));
  }

  final netWorth = ref.watch(netWorthWithLoansProvider);
  return NetWorthTrend.available([
    for (var i = 6; i >= 0; i--)
      _round2(
        netWorth -
            replay
                .where((r) => !r.at.isBefore(today.add(Duration(days: 1 - i))))
                .fold(0.0, (sum, r) => sum + r.effect),
      ),
  ]);
});

// ---------------------------------------------------------------------------
// Cash flow by week of this month
// ---------------------------------------------------------------------------

typedef WeeklyCashFlowBucket = ({String label, double net});

/// One stable period key per calendar month: `DateRange` has no value
/// equality, so building a fresh range on every read would create a new
/// family entry each time instead of reusing the computed lines.
final _thisMonthKeyProvider =
    Provider.family<({CashFlowPeriod period, DateRange range}), (int, int)>((
      ref,
      yearMonth,
    ) {
      const period = CashFlowPeriod.preset(CashFlowPreset.thisMonth);
      return (
        period: period,
        range: period.rangeFor(DateTime(yearMonth.$1, yearMonth.$2, 1)),
      );
    });

/// This month's net cash flow in four day-of-month buckets (1–7, 8–14,
/// 15–21, 22–end), built from the exact Money In / Money Out lines
/// [cashFlowThisMonthProvider] totals — so the bars always add up to the net
/// figure shown beside them. Presentation only: no line is re-classified.
final dashboardWeeklyCashFlowProvider = Provider<List<WeeklyCashFlowBucket>>((
  ref,
) {
  final now = DateTime.now();
  final key = ref.watch(_thisMonthKeyProvider((now.year, now.month)));
  final totals = List<double>.filled(4, 0);
  int bucket(DateTime d) => d.day <= 7
      ? 0
      : d.day <= 14
      ? 1
      : d.day <= 21
      ? 2
      : 3;
  for (final line in ref.watch(moneyInLinesForRangeFamilyProvider(key))) {
    totals[bucket(line.date)] += line.amount;
  }
  for (final line in ref.watch(moneyOutLinesForRangeFamilyProvider(key))) {
    totals[bucket(line.date)] -= line.amount;
  }
  final lastDay = now.endOfMonth.day;
  const labels = ['1–7', '8–14', '15–21'];
  return [
    for (var i = 0; i < 3; i++) (label: labels[i], net: _round2(totals[i])),
    (label: '22–$lastDay', net: _round2(totals[3])),
  ];
});

// ---------------------------------------------------------------------------
// Attention strip
// ---------------------------------------------------------------------------

typedef DashboardAttention = ({
  List<UpcomingDueItem> overdue,
  double overdueTotal,
  UpcomingDueItem? next,
});

/// What needs attention now, from the same [upcomingDueProvider] items (and
/// the same default cycle window) the Dashboard summary already uses: every
/// outgoing item already past its due date, plus the next one coming up.
/// Split-expense rows are money owed TO me and are never an obligation, so
/// they stay out of this strip.
final dashboardAttentionProvider = Provider<DashboardAttention>((ref) {
  final cycle = const SalaryCycleFull().resolve(DateTime.now());
  final items = ref
      .watch(upcomingDueProvider((start: cycle.start, end: cycle.end)))
      .where((i) => i.kind != UpcomingDueKind.splitExpense)
      .toList();
  final today = DateTime.now().dateOnly;
  final overdue =
      items.where((i) => i.dueDate.dateOnly.isBefore(today)).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final upcoming =
      items.where((i) => !i.dueDate.dateOnly.isBefore(today)).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return (
    overdue: overdue,
    overdueTotal: _round2(overdue.fold(0.0, (s, i) => s + i.remaining)),
    next: upcoming.firstOrNull,
  );
});

// ---------------------------------------------------------------------------
// Refresh + preferences
// ---------------------------------------------------------------------------

/// Every Firestore stream the Dashboard's figures are derived from.
/// Invalidating them re-subscribes each listener (served from the local
/// cache first, then the server), and every derived provider recomputes.
final List<ProviderOrFamily> dashboardSourceStreams = [
  transactionsStreamProvider,
  accountsStreamProvider,
  creditCardsStreamProvider,
  sharedCreditLimitsStreamProvider,
  statementsStreamProvider,
  loansStreamProvider,
  loansTrashStreamProvider,
  emisStreamProvider,
  installmentsStreamProvider,
  billsStreamProvider,
  peopleStreamProvider,
  ledgerStreamProvider,
  expensesStreamProvider,
  categoriesStreamProvider,
];

void invalidateDashboardSources(WidgetRef ref) {
  for (final p in dashboardSourceStreams) {
    ref.invalidate(p);
  }
}

const _hideNetWorthKey = 'dashboard_hide_net_worth';

/// The Net Worth eye toggle, remembered on this device (Web keeps the same
/// preference, `hideNetWorth`, per browser).
class NetWorthHiddenController extends Notifier<bool> {
  @override
  bool build() {
    try {
      return LocalSettingsService.getBool(_hideNetWorthKey);
    } on StateError {
      return false; // settings not initialised (tests/previews)
    }
  }

  void toggle() {
    state = !state;
    try {
      LocalSettingsService.setBool(_hideNetWorthKey, state);
    } on StateError {
      // Not persisted when settings aren't initialised; the toggle still
      // applies for this session.
    }
  }
}

final netWorthHiddenProvider = NotifierProvider<NetWorthHiddenController, bool>(
  NetWorthHiddenController.new,
);
