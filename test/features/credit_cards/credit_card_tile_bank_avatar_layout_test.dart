import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/card_network.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_status.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/screens/credit_cards_screen.dart';

/// Guards the worst case for the tile's header Row after adding the bank
/// avatar: a long card name + network icon + last-4 + an inactive status
/// chip, all sharing one Row on a 360dp phone.
const _smallPhone = Size(360, 640);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  testWidgets('credit card tile with bank avatar + network + status chip fits a small phone', (tester) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final account = Account(
      id: 'acc1',
      name: 'HDFC Millennia Rewards Platinum',
      type: AccountType.card,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF000000,
      createdAt: DateTime(2026, 1, 1),
      bankId: 'hdfc',
    );
    final card = CreditCardProfile(
      id: 'card1',
      accountId: 'acc1',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 2000000,
      createdAt: DateTime(2026, 1, 1),
      cardNetwork: CardNetwork.mastercard,
      lastFourDigits: '4321',
      status: CreditCardStatus.blocked,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
          statementsStreamProvider('card1').overrideWith((ref) => Stream.value(const [])),
          creditCardStandingProvider('card1').overrideWithValue(
            (outstanding: 1234567.89, available: 765432.11, currentCycleSpend: 0),
          ),
        ],
        child: const MaterialApp(home: CreditCardsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('HDFC Millennia Rewards Platinum •••• 4321'), findsOneWidget);
  });
}
