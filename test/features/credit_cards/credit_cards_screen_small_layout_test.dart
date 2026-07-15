import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/screens/credit_cards_screen.dart';

/// 360x640 is the standard small Android phone. The card tile packs three
/// stats into one Row, so each column is only a third of that width and
/// "Remaining to Pay" wraps to two lines — the case this guards.
const _smallPhone = Size(360, 640);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  testWidgets('card tile fits a small phone and keeps its stat values aligned', (tester) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final card = CreditCardProfile(
      id: 'card1',
      accountId: 'acc1',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 2000000,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
          statementsStreamProvider('card1').overrideWith((ref) => Stream.value(const [])),
          // Worst case: a long formatted amount under the longest label.
          creditCardStandingProvider('card1').overrideWithValue(
            (outstanding: 1234567.89, available: 765432.11, currentCycleSpend: 0),
          ),
        ],
        child: const MaterialApp(home: CreditCardsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remaining to Pay'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Next due'), findsOneWidget);

    // Each stat renders its value above its label. Without the Row's
    // CrossAxisAlignment.start, the wrapped two-line label re-centres its
    // column and drops the value ~8px below the other two.
    final valueTops = <double>[];
    for (final label in ['Remaining to Pay', 'Available', 'Next due']) {
      final column = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
      final valueText = find.descendant(of: column, matching: find.byType(Text)).first;
      valueTops.add(tester.getTopLeft(valueText).dy);
    }
    expect(valueTops.toSet().length, 1, reason: 'stat values must share one top edge: $valueTops');
  });
}
