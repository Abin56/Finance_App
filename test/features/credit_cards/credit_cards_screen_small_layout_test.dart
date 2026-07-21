import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/screens/credit_cards_screen.dart';

/// 360x640 is the standard small Android phone. The "All Cards" list tile
/// packs a card-face thumbnail, name/due-date column, and an Available
/// figure into one Row — the case this guards against overflow/wrapping.
const _smallPhone = Size(360, 640);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  testWidgets('all-cards list tile fits a small phone without overflow', (tester) async {
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

    final account = Account(
      id: 'acc1',
      name: 'A Very Long Test Card Nickname',
      type: AccountType.card,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF000000,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
          sharedCreditLimitsStreamProvider.overrideWith((ref) => Stream.value(const [])),
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

    // No RenderFlex overflow assertions from pumpAndSettle above means the
    // header and hero carousel fit. The summary card and list tile are
    // further down this 640px-tall viewport, so scroll to bring them into
    // the sliver's built extent before asserting on their content.
    expect(find.text('My Cards'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Total Credit Limit'), findsOneWidget);
    expect(find.text('All Cards (1)'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
