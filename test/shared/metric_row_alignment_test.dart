import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/cash_flow/presentation/widgets/payments_due_card.dart';
import 'package:finance_app/features/dashboard/presentation/widgets/dashboard_spending_snapshot_card.dart';
import 'package:finance_app/features/reports/presentation/widgets/reports_overview_card.dart';

/// Cards that lay 3+ stats across one Row on a small (360dp) phone.
///
/// Each stat is a Column of value + label. When a label wraps, that column
/// grows taller than its neighbours, and a Row left on its default centre
/// alignment then drops the shorter columns' text out of line. Every Row here
/// therefore sets `CrossAxisAlignment.start`.
///
/// Which label wraps depends on the font, so these assert across several text
/// scales rather than one: no single scale catches every case, and the test
/// font's metrics differ from the device's.
const _smallPhone = Size(360, 640);
const _scales = [1.0, 1.3, 2.0];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  Future<void> pumpAt(WidgetTester tester, double scale, List<Override> overrides, Widget child) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          // MediaQuery must go inside MaterialApp, which otherwise inserts its
          // own from the view and discards an outer one.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: inner!,
          ),
          // A ListView, because the real screens scroll: a bare Scaffold body
          // would stretch every Column to full height and hide the bug.
          home: Scaffold(body: ListView(children: [child])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Each stat's first Text must share one top edge with the others.
  void expectStatsAligned(WidgetTester tester, List<String> labels) {
    final tops = <String, double>{};
    for (final label in labels) {
      final column = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
      final texts = find.descendant(of: column, matching: find.byType(Text));
      tops[label] = tester.getTopLeft(texts.at(0)).dy;
    }
    expect(tops.values.toSet().length, 1, reason: 'stat text must share one top edge, got $tops');
  }

  const bd = (due: 123456.78, paid: 23456.78, remaining: 100000.0);

  for (final scale in _scales) {
    testWidgets('ReportsOverviewCard stats stay aligned @${scale}x', (tester) async {
      await pumpAt(tester, scale, const [], const ReportsOverviewCard(
        income: 1234567.89,
        expenses: 987654.32,
        incomeChangePercent: 12.5,
        expensesChangePercent: -8.3,
        netSavingsChangePercent: 4.1,
      ));
      expectStatsAligned(tester, ['Total Income', 'Total Expenses', 'Net Savings']);
    });

    testWidgets('DashboardSpendingSnapshotCard stats stay aligned @${scale}x', (tester) async {
      await pumpAt(
        tester,
        scale,
        const [],
        const DashboardSpendingSnapshotCard(
          todayIncome: 1234567.89,
          todayExpense: 987654.32,
          monthIncome: 1234567.89,
          monthExpense: 987654.32,
          hasAnyTransactions: true,
        ),
      );
      // 'Net' (not 'Savings') is unique to the Today row, so this pins down
      // one row unambiguously — both rows share the same stat layout, so
      // this still covers the shared component the bug lived in.
      expectStatsAligned(tester, ['Income', 'Expense', 'Net']);
    });

    testWidgets('PaymentsDueCard footer stats stay aligned @${scale}x', (tester) async {
      await pumpAt(tester, scale, [
        totalDueThisMonthProvider.overrideWithValue(bd),
        creditCardDueThisMonthBreakdownProvider.overrideWithValue(bd),
        emiDueThisMonthBreakdownProvider.overrideWithValue(bd),
        loanDueThisMonthBreakdownProvider.overrideWithValue(bd),
        billsDueThisMonthBreakdownProvider.overrideWithValue(bd),
        otherScheduledDueThisMonthBreakdownProvider.overrideWithValue(bd),
      ], const PaymentsDueCard());
      expectStatsAligned(tester, ['Total Due', 'Already Paid', 'Remaining']);
    });

  }
}

// PersonStatementHeader carries the same fix but is deliberately not covered
// here. The default `flutter test` font draws every glyph as a full-em square,
// so text measures roughly twice its real width; that pushes this card's
// "Last transaction" row into a RenderFlex overflow which does not happen on a
// device (checked against real font metrics at 1.0x/1.3x/2.0x). Asserting on it
// here would fail on an artifact rather than a bug.
