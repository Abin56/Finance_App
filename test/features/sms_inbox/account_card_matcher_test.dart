import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Account account({
    required String id,
    required String name,
    String? bankId,
    String? last4,
  }) {
    return Account(
      id: id,
      name: name,
      type: AccountType.bank,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF000000,
      createdAt: DateTime(2026, 1, 1),
      bankId: bankId,
      accountNumberLast4: last4,
    );
  }

  CreditCardProfile card({
    required String id,
    required String accountId,
    String? last4,
  }) {
    return CreditCardProfile(
      id: id,
      accountId: accountId,
      statementDay: 1,
      paymentDueDay: 15,
      creditLimit: 100000,
      createdAt: DateTime(2026, 1, 1),
      lastFourDigits: last4,
    );
  }

  ParsedSmsTransaction parsed({
    double amount = 1250,
    String? bankName,
    String? maskedAccountOrCard,
  }) {
    return ParsedSmsTransaction(
      amount: amount,
      direction: SmsTransactionDirection.debit,
      dateTime: DateTime(2026, 7, 15),
      category: SmsTransactionCategory.creditCardPurchase,
      confidence: 0.85,
      rawBody: 'irrelevant',
      bankName: bankName,
      maskedAccountOrCard: maskedAccountOrCard,
    );
  }

  test('resolves a credit card by last-4 and confirms the bank', () {
    final hdfcAccount = account(id: 'acc-1', name: 'HDFC Card', bankId: 'hdfc');
    final hdfcCard = card(id: 'card-1', accountId: 'acc-1', last4: '1234');
    final matcher = AccountCardMatcher(
      accounts: [hdfcAccount],
      cards: [hdfcCard],
    );

    final result = matcher.match(
      parsed(bankName: 'HDFC Bank', maskedAccountOrCard: '1234'),
    );

    expect(result.isResolved, isTrue);
    expect(result.matchedCardId, 'card-1');
    expect(result.matchedAccountId, 'acc-1');
    expect(result.bankConfirmed, isTrue);
  });

  test('resolves a plain bank account by last-4 (SBI)', () {
    final sbiAccount = account(
      id: 'acc-2',
      name: 'SBI Savings',
      bankId: 'sbi',
      last4: '5678',
    );
    final matcher = AccountCardMatcher(accounts: [sbiAccount], cards: const []);

    final result = matcher.match(
      parsed(bankName: 'State Bank of India', maskedAccountOrCard: '5678'),
    );

    expect(result.isResolved, isTrue);
    expect(result.matchedAccountId, 'acc-2');
    expect(result.matchedCardId, isNull);
    expect(result.bankConfirmed, isTrue);
  });

  test('resolves by last-4 alone when the bank cannot be confirmed', () {
    final hdfcAccount = account(id: 'acc-1', name: 'HDFC Card', bankId: 'hdfc');
    final hdfcCard = card(id: 'card-1', accountId: 'acc-1', last4: '1234');
    final matcher = AccountCardMatcher(
      accounts: [hdfcAccount],
      cards: [hdfcCard],
    );

    // Sender didn't resolve to a known bank name at all.
    final result = matcher.match(
      parsed(bankName: null, maskedAccountOrCard: '1234'),
    );

    expect(result.isResolved, isTrue);
    expect(result.matchedCardId, 'card-1');
    expect(result.bankConfirmed, isFalse);
  });

  test('flags a bank mismatch as still resolved but not bank-confirmed', () {
    final hdfcAccount = account(id: 'acc-1', name: 'HDFC Card', bankId: 'hdfc');
    final hdfcCard = card(id: 'card-1', accountId: 'acc-1', last4: '1234');
    final matcher = AccountCardMatcher(
      accounts: [hdfcAccount],
      cards: [hdfcCard],
    );

    // last-4 coincidentally matches this card, but the SMS is from a
    // different bank entirely.
    final result = matcher.match(
      parsed(bankName: 'ICICI Bank', maskedAccountOrCard: '1234'),
    );

    expect(result.isResolved, isTrue);
    expect(result.matchedCardId, 'card-1');
    expect(result.bankConfirmed, isFalse);
  });

  test('never guesses when two cards share the same last-4', () {
    final acc1 = account(id: 'acc-1', name: 'HDFC Card', bankId: 'hdfc');
    final acc2 = account(id: 'acc-2', name: 'ICICI Card', bankId: 'icici');
    final card1 = card(id: 'card-1', accountId: 'acc-1', last4: '1234');
    final card2 = card(id: 'card-2', accountId: 'acc-2', last4: '1234');
    final matcher = AccountCardMatcher(
      accounts: [acc1, acc2],
      cards: [card1, card2],
    );

    final result = matcher.match(parsed(maskedAccountOrCard: '1234'));

    expect(result.isResolved, isFalse);
    expect(result.matchedAccountId, isNull);
    expect(result.alternatives, hasLength(2));
  });

  test(
    'a bank match with no last-4 is only ever a suggestion, never resolved',
    () {
      final hdfcAccount = account(
        id: 'acc-1',
        name: 'HDFC Savings',
        bankId: 'hdfc',
        last4: '9999',
      );
      final matcher = AccountCardMatcher(
        accounts: [hdfcAccount],
        cards: const [],
      );

      final result = matcher.match(
        parsed(bankName: 'HDFC Bank', maskedAccountOrCard: null),
      );

      expect(result.isResolved, isFalse);
      expect(result.alternatives, hasLength(1));
      expect(result.alternatives.single.accountId, 'acc-1');
    },
  );

  test('no signal at all matches nothing', () {
    final hdfcAccount = account(
      id: 'acc-1',
      name: 'HDFC Savings',
      bankId: 'hdfc',
      last4: '9999',
    );
    final matcher = AccountCardMatcher(
      accounts: [hdfcAccount],
      cards: const [],
    );

    final result = matcher.match(
      parsed(bankName: 'Axis Bank', maskedAccountOrCard: '4321'),
    );

    expect(result.isResolved, isFalse);
    expect(result.alternatives, isEmpty);
  });

  test(
    'an account already represented by its card is not also offered as a plain account',
    () {
      // Regression: without the accountId exclusion, this account's own
      // accountNumberLast4 could add a second, redundant target alongside its
      // CreditCardProfile's lastFourDigits.
      final hdfcAccount = account(
        id: 'acc-1',
        name: 'HDFC Card',
        bankId: 'hdfc',
        last4: '1234',
      );
      final hdfcCard = card(id: 'card-1', accountId: 'acc-1', last4: '1234');
      final matcher = AccountCardMatcher(
        accounts: [hdfcAccount],
        cards: [hdfcCard],
      );

      final result = matcher.match(parsed(maskedAccountOrCard: '1234'));

      expect(result.isResolved, isTrue);
      expect(result.matchedCardId, 'card-1');
    },
  );
}
