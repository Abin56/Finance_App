import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/shared_credit_limit.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/screens/credit_cards_screen.dart';

const _smallPhone = Size(360, 640);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<CreditCardProfile> cards,
    required List<Account> accounts,
    required SharedCreditLimit sharedLimit,
    required CreditCardStanding facilityStanding,
    required Map<String, CreditCardStanding> perCardStanding,
  }) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(accounts)),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(cards)),
          sharedCreditLimitsStreamProvider.overrideWith((ref) => Stream.value([sharedLimit])),
          for (final card in cards) statementsStreamProvider(card.id).overrideWith((ref) => Stream.value(const [])),
          sharedCreditLimitStandingProvider(sharedLimit.id).overrideWithValue(facilityStanding),
          for (final entry in perCardStanding.entries)
            creditCardStandingProvider(entry.key).overrideWithValue(entry.value),
        ],
        child: const MaterialApp(home: CreditCardsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('two-card facility renders the hero summary and linked cards row without overflow', (tester) async {
    final sharedLimit = SharedCreditLimit(
      id: 'shared1',
      name: 'HDFC',
      creditLimit: 500000,
      createdAt: DateTime(2026, 1, 1),
    );
    final card1 = CreditCardProfile(
      id: 'card1',
      accountId: 'acc1',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 0,
      createdAt: DateTime(2026, 1, 1),
      sharedLimitId: 'shared1',
      lastFourDigits: '7960',
    );
    final card2 = CreditCardProfile(
      id: 'card2',
      accountId: 'acc2',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 0,
      createdAt: DateTime(2026, 1, 1),
      sharedLimitId: 'shared1',
      lastFourDigits: '2485',
    );
    final account1 = Account(
      id: 'acc1',
      name: 'HDFC Visa',
      type: AccountType.card,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF1565C0,
      createdAt: DateTime(2026, 1, 1),
    );
    final account2 = Account(
      id: 'acc2',
      name: 'HDFC RuPay',
      type: AccountType.card,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF6A1B9A,
      createdAt: DateTime(2026, 1, 1),
    );

    await pumpScreen(
      tester,
      cards: [card1, card2],
      accounts: [account1, account2],
      sharedLimit: sharedLimit,
      facilityStanding: (outstanding: 345678.9, available: 154321.1, currentCycleSpend: 0),
      perCardStanding: {
        'card1': (outstanding: 200000, available: 300000, currentCycleSpend: 0),
        'card2': (outstanding: 145678.9, available: 354321.1, currentCycleSpend: 0),
      },
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('HDFC Shared Credit Limit'), findsOneWidget);
    expect(find.text('Available Credit'), findsOneWidget);
    expect(find.text('2 physical cards'), findsOneWidget);
    expect(find.text('Add another card'), findsOneWidget);
    expect(find.textContaining('% used'), findsOneWidget);

    final addButton = find.widgetWithText(TextButton, 'Add another card');
    expect(addButton, findsOneWidget);
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    final buttonRect = tester.getRect(addButton);
    expect(buttonRect.right, lessThanOrEqualTo(_smallPhone.width), reason: 'button overflows screen width');

    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add Another Physical Card'), findsOneWidget);
    expect(
      find.textContaining('This card will use the same approved credit limit'),
      findsOneWidget,
    );
    expect(find.text('Bill generated on'), findsOneWidget);
  });

  testWidgets('single-card facility still shows its physical-card count and add-another affordance', (
    tester,
  ) async {
    final sharedLimit = SharedCreditLimit(
      id: 'shared1',
      name: 'HDFC',
      creditLimit: 500000,
      createdAt: DateTime(2026, 1, 1),
    );
    final card1 = CreditCardProfile(
      id: 'card1',
      accountId: 'acc1',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 0,
      createdAt: DateTime(2026, 1, 1),
      sharedLimitId: 'shared1',
      lastFourDigits: '7960',
    );
    final account1 = Account(
      id: 'acc1',
      name: 'HDFC Visa',
      type: AccountType.card,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF1565C0,
      createdAt: DateTime(2026, 1, 1),
    );

    await pumpScreen(
      tester,
      cards: [card1],
      accounts: [account1],
      sharedLimit: sharedLimit,
      facilityStanding: (outstanding: 100000, available: 400000, currentCycleSpend: 0),
      perCardStanding: {'card1': (outstanding: 100000, available: 400000, currentCycleSpend: 0)},
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1 physical card'), findsOneWidget);
    expect(find.text('Add another card'), findsOneWidget);
  });
}
