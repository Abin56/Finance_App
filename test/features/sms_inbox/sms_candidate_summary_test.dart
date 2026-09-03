import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/card_network.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
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

  FinancialEvent financialEvent({
    String smsItemId = 'sms-1',
    String? matchedAccountId,
    String? matchedCardId,
    ConfidenceLevel level = ConfidenceLevel.high,
    bool needsReview = false,
    List<String> reasons = const [],
    FinancialEventType eventType = FinancialEventType.payment,
    String? subcategory,
  }) {
    return FinancialEvent(
      id: 'evt-$smsItemId',
      primarySmsItemId: smsItemId,
      eventType: eventType,
      role: FinancialEventRole.standalone,
      status: FinancialEventStatus.pendingReview,
      direction: SmsTransactionDirection.debit,
      amount: const FieldConfidence(
        value: 1250,
        confidence: 0.9,
        source: EvidenceSource.bothAgree,
      ),
      merchant: const FieldConfidence.unknown(),
      category: const FieldConfidence.unknown(),
      paymentMethod: const FieldConfidence<PaymentMethod>.unknown(),
      accountMatch: FieldConfidence(
        value: matchedAccountId,
        confidence: matchedAccountId == null ? 0.0 : 1.0,
        source: EvidenceSource.regexOnly,
      ),
      matchedCardId: matchedCardId,
      moneyMovement: const FieldConfidence(
        value: true,
        confidence: 0.9,
        source: EvidenceSource.bothAgree,
      ),
      transactionStatus: const FieldConfidence.unknown(),
      eventDate: DateTime(2026, 7, 15),
      overallConfidence: 0.9,
      confidenceLevel: level,
      automationAction: AutomationAction.needsReview,
      needsReview: needsReview,
      reviewReasons: reasons,
      createdAt: DateTime(2026, 7, 15),
      subcategory: subcategory,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required List<TransactionCandidate> candidates,
    List<Account> accounts = const [],
    List<CreditCardProfile> cards = const [],
    FinancialEvent? event,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionCandidatesProvider.overrideWith((ref) async => candidates),
          accountsStreamProvider.overrideWith((ref) => Stream.value(accounts)),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(cards)),
          financialEventForSmsItemProvider.overrideWith(
            (ref, smsItemId) async => event,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SmsCandidateSummary(smsItemId: 'sms-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders nothing when no candidate exists for this SMS', (
    tester,
  ) async {
    await pump(tester, candidates: const []);

    expect(find.byType(SmsCandidateSummary), findsOneWidget);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('shows the matched card name and a High badge', (tester) async {
    await pump(
      tester,
      candidates: [
        candidate(matchedAccountId: 'acc-1', matchedCardId: 'card-1'),
      ],
      accounts: [hdfcAccount],
      cards: [hdfcCard],
    );

    expect(find.textContaining('HDFC Card'), findsOneWidget);
    expect(find.textContaining('1234'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
  });

  testWidgets('says the account needs review when unresolved', (tester) async {
    await pump(
      tester,
      candidates: [candidate(level: ConfidenceLevel.low, needsReview: true)],
    );

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
          reasons: const [
            'Could not confidently determine what kind of transaction this is.',
          ],
        ),
      ],
      accounts: [hdfcAccount],
    );

    expect(
      find.text(
        'Could not confidently determine what kind of transaction this is.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'prefers a FinancialEvent over a TransactionCandidate when both exist, and shows its event-type chip',
    (tester) async {
      await pump(
        tester,
        candidates: [
          candidate(matchedAccountId: 'acc-1', matchedCardId: 'card-1'),
        ],
        accounts: [hdfcAccount],
        cards: [hdfcCard],
        event: financialEvent(
          matchedAccountId: 'acc-1',
          matchedCardId: 'card-1',
          eventType: FinancialEventType.refund,
        ),
      );

      expect(find.text('Refund'), findsOneWidget);
      expect(find.textContaining('HDFC Card'), findsOneWidget);
    },
  );

  testWidgets('shows the AI-derived subcategory as a caption when set', (
    tester,
  ) async {
    await pump(
      tester,
      candidates: const [],
      event: financialEvent(subcategory: 'Food Delivery'),
    );

    expect(find.text('Food Delivery'), findsOneWidget);
  });

  testWidgets(
    'falls back to the TransactionCandidate display when no FinancialEvent exists for this SMS',
    (tester) async {
      await pump(
        tester,
        candidates: [
          candidate(matchedAccountId: 'acc-1', matchedCardId: 'card-1'),
        ],
        accounts: [hdfcAccount],
        cards: [hdfcCard],
        event: null,
      );

      expect(find.textContaining('HDFC Card'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      // No event-type chip in the legacy path — there is no equivalent concept.
      expect(find.text('Payment'), findsNothing);
    },
  );
}
