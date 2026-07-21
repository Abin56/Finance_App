import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/widgets/credit_card_form_sheet.dart';

/// A credit card's display name is always computed from bank + network +
/// last-4 (see [cardDisplayName]) — there is no manual "Card name" field to
/// duplicate what the bank picker/network dropdown already say.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          sharedCreditLimitsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: Scaffold(body: CreditCardFormSheet())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('has no manual Card name field', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(TextFormField, 'Card name'), findsNothing);
    expect(find.text('Shown as "Credit Card"'), findsOneWidget);
  });

  testWidgets('picking a bank and network updates the computed name preview', (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.text('Select bank (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select bank (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDFC Bank'));
    await tester.pumpAndSettle();

    expect(find.text('Shown as "HDFC"'), findsOneWidget);

    await tester.ensureVisible(find.text('Visa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visa'));
    await tester.pumpAndSettle();

    expect(find.text('Shown as "HDFC Visa"'), findsOneWidget);
  });
}
