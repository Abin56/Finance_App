import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/card_network.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_candidate_summary.dart';

void main() {
  final hdfcAccount = Account(
    id: 'acc-1',
    name: 'HDFC Card',
    type: AccountType.card,
    openingBalance: 0,
    currentBalance: 0,
    colorValue: 0xFF000000,
    createdAt: DateTime(2026, 1, 1),
    bankId: 'hdfc',
  );

  final hdfcCard = CreditCardProfile(
    id: 'card-1',
    accountId: 'acc-1',
    statementDay: 1,
    paymentDueDay: 15,
    creditLimit: 100000,
    createdAt: DateTime(2026, 1, 1),
    lastFourDigits: '1234',
    cardNetwork: CardNetwork.visa,
  );

  TransactionCandidate candidate({
    String smsItemId = 'sms-1',
    String? matchedAccountId,
    String? matchedCardId,
    ConfidenceLevel level = ConfidenceLevel.high,
    bool needsReview = false,
    List<String> reasons = const [],
  }) {
    return TransactionCandidate(
      id: 'cand-$smsItemId',
      smsItemId: smsItemId,
      amount: 1250,
      direction: SmsTransactionDirection.debit,
      eventType: SmsTransactionCategory.creditCardPurchase,
      transactionDate: DateTime(2026, 7, 15),
      matchedAccountId: matchedAccountId,
      matchedCardId: matchedCardId,
      confidenceLevel: level,
      confidenceScore: 0.9,
      needsReview: needsReview,
      reviewReasons: reasons,
      createdAt: DateTime(2026, 7, 15),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required List<TransactionCandidate> candidates,
    List<Account> accounts = const [],
    List<CreditCardProfile> cards = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionCandidatesProvider.overrideWith((ref) async => candidates),
          accountsStreamProvider.overrideWith((ref) => Stream.value(accounts)),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(cards)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SmsCandidateSummary(smsItemId: 'sms-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders nothing when no candidate exists for this SMS', (tester) async {
    await pump(tester, candidates: const []);

    expect(find.byType(SmsCandidateSummary), findsOneWidget);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('shows the matched card name and a High badge', (tester) async {
    await pump(
      tester,
      candidates: [candidate(matchedAccountId: 'acc-1', matchedCardId: 'card-1')],
      accounts: [hdfcAccount],
      cards: [hdfcCard],
    );

    expect(find.textContaining('HDFC Card'), findsOneWidget);
    expect(find.textContaining('1234'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
  });

  testWidgets('says the account needs review when unresolved', (tester) async {
    await pump(tester, candidates: [candidate(level: ConfidenceLevel.low, needsReview: true)]);

    expect(find.text('Account needs review'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
  });

  testWidgets('lists every review reason', (tester) async {
    await pump(
      tester,
      candidates: [
        candidate(
          matchedAccountId: 'acc-1',
          level: ConfidenceLevel.medium,
          needsReview: true,
          reasons: const ['Could not confidently determine what kind of transaction this is.'],
        ),
      ],
      accounts: [hdfcAccount],
    );

    expect(find.text('Could not confidently determine what kind of transaction this is.'), findsOneWidget);
  });
}
