import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_stats.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_stats_providers.dart';
import 'package:finance_app/features/accounts/presentation/screens/account_detail_screen.dart';

/// 360x640 is the standard small Android phone. The stats card packs two
/// stat columns per Row (mirroring DashboardSpendingSnapshotCard's 3-per-row
/// layout), so this guards against a large formatted amount or a long label
/// pushing a column's text out of alignment or off-screen — see
/// test/shared/metric_row_alignment_test.dart for the same concern on other
/// stat rows.
const _smallPhone = Size(360, 640);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('balance/stats/monthly spending fit a small phone without overflow @${scale}x', (tester) async {
      tester.view.physicalSize = _smallPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final account = Account(
        id: 'acc1',
        name: 'HDFC Savings Account Number Two',
        type: AccountType.bank,
        openingBalance: 0,
        // Worst case: a long formatted balance under a long account name.
        currentBalance: 1234567.89,
        colorValue: 0xFF000000,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
            accountStatsProvider('acc1').overrideWithValue(
              const AccountStats(
                income: 1234567.89,
                expense: 987654.32,
                transfersIn: 555555.55,
                transfersOut: 444444.44,
                currentMonthExpense: 123456.78,
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const AccountDetailScreen(accountId: 'acc1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // At larger text scales the body legitimately grows taller than a
      // small phone's viewport — that's normal ListView scrolling, not an
      // overflow bug, so scroll to confirm the button exists rather than
      // asserting it's already on-screen.
      await tester.scrollUntilVisible(find.text('View Full History'), 200);
      expect(find.text('View Full History'), findsOneWidget);
    });
  }
}
