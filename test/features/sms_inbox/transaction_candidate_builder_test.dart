import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rawMessage = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: 'Rs.1,250.00 spent on your HDFC Credit Card ending 1234 at Amazon.',
    date: DateTime(2026, 7, 15, 10),
  );

  SmsInboxItem item({String id = 'sms-1', ParsedSmsTransaction? parsed}) {
    return SmsInboxItem(
      id: id,
      messageKey: 'key-$id',
      rawMessage: rawMessage,
      parsed: parsed,
      dedupKey: 'dedup-$id',
      status: SmsImportStatus.pending,
      createdAt: DateTime(2026, 7, 15, 10),
    );
  }

  final parsedTxn = ParsedSmsTransaction(
    amount: 1250,
    direction: SmsTransactionDirection.debit,
    dateTime: DateTime(2026, 7, 15, 10),
    category: SmsTransactionCategory.creditCardPurchase,
    confidence: 0.85,
    rawBody: rawMessage.body,
    merchantOrSender: 'Amazon',
    bankName: 'HDFC Bank',
    maskedAccountOrCard: '1234',
    referenceNumber: 'REF123',
  );

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
  );

  test('returns null for an item with no parsed result', () {
    final matcher = AccountCardMatcher(accounts: const [], cards: const []);
    final builder = TransactionCandidateBuilder(matcher);

    expect(builder.build(item(parsed: null)), isNull);
  });

  test('builds a High-confidence candidate when the card resolves cleanly', () {
    final matcher = AccountCardMatcher(
      accounts: [hdfcAccount],
      cards: [hdfcCard],
    );
    final builder = TransactionCandidateBuilder(matcher);

    final candidate = builder.build(item(parsed: parsedTxn));

    expect(candidate, isNotNull);
    expect(candidate!.smsItemId, 'sms-1');
    expect(candidate.matchedAccountId, 'acc-1');
    expect(candidate.matchedCardId, 'card-1');
    expect(candidate.confidenceLevel, ConfidenceLevel.high);
    expect(candidate.needsReview, isFalse);
    expect(candidate.amount, 1250);
    expect(candidate.eventType, SmsTransactionCategory.creditCardPurchase);
  });

  test('needsReview is true when no account can be matched', () {
    final matcher = AccountCardMatcher(accounts: const [], cards: const []);
    final builder = TransactionCandidateBuilder(matcher);

    final candidate = builder.build(item(parsed: parsedTxn));

    expect(candidate!.matchedAccountId, isNull);
    expect(candidate.confidenceLevel, ConfidenceLevel.low);
    expect(candidate.needsReview, isTrue);
    expect(candidate.reviewReasons, isNotEmpty);
  });
}
