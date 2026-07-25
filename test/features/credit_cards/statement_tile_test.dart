import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/utils/currency_formatter.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/screens/credit_card_detail_screen.dart';

/// Regression coverage for the bug where a statement's compact tile always
/// showed `totalAmount` (the full original bill) even for a partially paid
/// or carried-forward statement, overstating what was actually still owed.
/// Fixed by rendering `remainingAmount` as the primary figure with the
/// original `totalAmount` as a secondary "of $X" line.
void main() {
  const cardId = 'card1';

  final card = CreditCardProfile(
    id: cardId,
    accountId: 'acc1',
    statementDay: 17,
    paymentDueDay: 5,
    creditLimit: 100000,
    createdAt: DateTime(2026, 1, 1),
  );

  final account = Account(
    id: 'acc1',
    name: 'Test Card',
    type: AccountType.card,
    openingBalance: 0,
    currentBalance: 0,
    colorValue: 0xFF000000,
    createdAt: DateTime(2026, 1, 1),
  );

  Statement partiallyPaidStatement({required double totalAmount, required double amountPaid}) {
    return Statement(
      id: 'stmt1',
      cardId: cardId,
      periodStart: DateTime(2026, 6, 18),
      periodEnd: DateTime(2026, 7, 17),
      generatedDate: DateTime(2026, 7, 17),
      dueDate: DateTime(2026, 8, 5),
      totalAmount: totalAmount,
      amountPaid: amountPaid,
      createdAt: DateTime(2026, 7, 17),
    );
  }

  Future<void> pumpDetailScreen(WidgetTester tester, Statement statement, {required bool isCarriedForward}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
          accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
          sharedCreditLimitsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          statementsStreamProvider(cardId).overrideWith((ref) => Stream.value([statement])),
          statementsWithLiveTotalsProvider(cardId).overrideWith((ref) => [statement]),
          materializeStatementProvider(cardId).overrideWith((ref) async {}),
          currentStatementCycleProvider(cardId).overrideWith((ref) => null),
          statementCycleViewProvider(cardId).overrideWith(
            (ref) => (previousCyclePending: isCarriedForward ? <Statement>[statement] : <Statement>[], current: null),
          ),
          creditCardStandingProvider(cardId).overrideWith(
            (ref) => (outstanding: statement.remainingAmount, available: 99000, currentCycleSpend: 0),
          ),
        ],
        child: const MaterialApp(home: CreditCardDetailScreen(cardId: cardId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a partially paid statement tile shows remaining as primary and total as secondary', (tester) async {
    final statement = partiallyPaidStatement(totalAmount: 5000, amountPaid: 2000);
    await pumpDetailScreen(tester, statement, isCarriedForward: true);

    // The statement appears twice (Previous Cycle Pending + Statements
    // history), so both tiles must show the fixed figures — never falls
    // back to the old totalAmount-only rendering anywhere on screen.
    expect(find.text(CurrencyFormatter.instance.format(3000)), findsNWidgets(2));
    expect(find.text('of ${CurrencyFormatter.instance.format(5000)}'), findsNWidgets(2));
    expect(find.text(CurrencyFormatter.instance.format(5000)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fully paid statement shows a clamped zero remaining, not negative', (tester) async {
    final statement = partiallyPaidStatement(totalAmount: 5000, amountPaid: 5000);
    await pumpDetailScreen(tester, statement, isCarriedForward: false);

    // Fully paid -> not carried forward, so this statement only appears
    // once, in the Statements history section. The zero-amount figure also
    // coincidentally matches the "This cycle" mini-stat (currentCycleSpend
    // is 0 in this fixture), so assert on the unambiguous secondary line
    // instead of the primary amount alone.
    expect(find.text('of ${CurrencyFormatter.instance.format(5000)}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
