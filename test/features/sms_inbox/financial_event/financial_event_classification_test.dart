import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end classification tests, deliberately run in **regex-only mode**
/// (no AI provider configured) against highly varied real-world wording —
/// not fixed bank templates — for every category the SMS AI rebuild plan's
/// Phase 2 explicitly asks to prove out. This is the honest baseline: what
/// FlowFi gets right *without* an AI call at all, which is what every user
/// experiences until the Cloud Function is deployed (and what it falls back
/// to whenever the AI call fails or is disabled). Where the deterministic
/// layer's answer is necessarily coarser than what AI could infer, the test
/// asserts the coarser-but-safe answer and a comment says so — never a wrong
/// or invented one.
void main() {
  const extractor = FinancialEventExtractor();
  const resolvedAccount = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    matchReason: 'Matched by last-4.',
  );

  /// Runs [body] through the real `SmsFinancialFilter` + `SmsParserRegistry`
  /// (exactly what a real scan does) before handing it to the extractor —
  /// so these tests exercise the actual end-to-end regex pipeline, not a
  /// hand-built `ParsedSmsTransaction`.
  Future<({SmsInboxItem item, bool passedFilter})> buildAndExtract(
    String body, {
    String sender = 'VM-HDFCBK',
  }) async {
    final message = RawSmsMessage(
      address: sender,
      body: body,
      date: DateTime(2026, 7, 15, 10),
    );
    final passedFilter = SmsFinancialFilter.isFinancial(message);
    final parsed = passedFilter
        ? const SmsParserRegistry().tryParse(message)
        : null;
    final item = SmsInboxItem(
      id: 'sms-1',
      messageKey: 'key-1',
      rawMessage: message,
      dedupKey: 'dedup-1',
      status: SmsImportStatus.pending,
      createdAt: DateTime(2026, 7, 15),
      parsed: parsed,
    );
    return (item: item, passedFilter: passedFilter);
  }

  group(
    '1. actual transaction (baseline — must always be a real money-movement event)',
    () {
      const variants = [
        'Rs 500 debited from your account for UPI payment to Swiggy.',
        'Your account has been debited by INR 500 towards a purchase.',
        'UPI payment of ₹500 to ABC completed.',
        'Payment successful. Amount ₹500 debited from a/c XX1234.',
        '₹500 sent to abc@upi.',
        'Transaction successful for INR 500 at a merchant.',
        'You have paid ₹500 to a merchant via UPI.',
        '₹500 credited to your account.',
        'Amount of ₹500 received in your account.',
      ];

      for (final body in variants) {
        test('"$body"', () async {
          final built = await buildAndExtract(body);
          expect(
            built.passedFilter,
            isTrue,
            reason: 'must pass the local financial candidate filter',
          );
          expect(built.item.parsed, isNotNull, reason: 'must be parseable');
          final event = await extractor.extract(
            item: built.item,
            accountMatch: resolvedAccount,
            categories: const [],
          );
          expect(event.moneyMovement.value, isTrue, reason: body);
          expect(event.amount.value, closeTo(500, 0.01));
        });
      }
    },
  );

  group('2. reminder — never a transaction, even with a valid amount', () {
    test('"Your EMI of ₹8,500 is due tomorrow."', () async {
      final built = await buildAndExtract(
        'Your EMI of Rs.8,500 is due tomorrow.',
      );
      // May or may not parse a direction depending on wording, but either
      // way moneyMovement must never end up true.
      if (built.item.parsed != null) {
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
        );
        expect(event.moneyMovement.value, isFalse);
        expect(event.eventType, FinancialEventType.reminder);
      }
    });

    test(
      '"₹8,500 will be debited towards your EMI tomorrow." (the exact false-positive case)',
      () async {
        // Contains "debited" — the keyword the old regex-only pipeline would
        // have matched as a completed transaction — but is future-tense.
        final built = await buildAndExtract(
          'Rs.8,500 will be debited towards your EMI tomorrow.',
        );
        expect(
          built.item.parsed,
          isNotNull,
          reason: 'the regex parser DOES find an amount+direction here',
        );
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
        );
        expect(
          event.moneyMovement.value,
          isFalse,
          reason: 'future-tense reminder wording must suppress money movement',
        );
        expect(event.eventType, FinancialEventType.reminder);
      },
    );

    test(
      '"Your payment of ₹8,500 is due tomorrow." never creates a transaction',
      () async {
        final built = await buildAndExtract(
          'Your payment of Rs.8,500 is due tomorrow. Kindly pay to avoid late fee.',
        );
        if (built.item.parsed != null) {
          final event = await extractor.extract(
            item: built.item,
            accountMatch: resolvedAccount,
            categories: const [],
          );
          expect(event.moneyMovement.value, isFalse);
        }
      },
    );
  });

  group('3. failed transaction', () {
    test('"Your payment of ₹8,500 failed."', () async {
      final built = await buildAndExtract(
        'Your payment of Rs.8,500 failed due to insufficient balance.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(
        event.moneyMovement.value,
        isFalse,
        reason: 'a failed transaction never implies money moved',
      );
      expect(event.transactionStatus.value, TransactionStatus.failed);
    });

    test('"UPI payment of ₹500 has failed."', () async {
      final built = await buildAndExtract(
        'UPI payment of Rs.500 has failed. Please try again.',
      );
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.moneyMovement.value, isFalse);
    });
  });

  group('4. pending transaction', () {
    test('"Your payment of ₹500 is pending confirmation."', () async {
      final built = await buildAndExtract(
        'Your payment of Rs.500 is pending confirmation from the bank.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.moneyMovement.value, isFalse);
      expect(event.transactionStatus.value, TransactionStatus.pending);
    });
  });

  group('5. successful transaction', () {
    test('"₹8,500 EMI payment successful."', () async {
      final built = await buildAndExtract(
        'Rs.8,500 EMI payment successful. Thank you.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.moneyMovement.value, isTrue);
      expect(event.transactionStatus.value, TransactionStatus.success);
    });
  });

  group('6. refund', () {
    test('"₹500 refunded."', () async {
      final built = await buildAndExtract(
        'Rs.500 refunded to your account by Swiggy.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.refund);
      expect(
        event.moneyMovement.value,
        isTrue,
        reason: 'a refund is itself a real (inverse) money movement',
      );
    });
  });

  group('7. reversal', () {
    test('"₹500 reversed."', () async {
      final built = await buildAndExtract(
        'Rs.500 debited on 10-Jul has been reversed to your account XX1234.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      // The deterministic-only override (no AI) resolves eventType via the
      // transactionStatus signal, since SmsTransactionCategory itself has no
      // "reversal" concept.
      expect(event.eventType, FinancialEventType.reversal);
      expect(event.transactionStatus.value, TransactionStatus.reversed);
      expect(event.moneyMovement.value, isTrue);
    });
  });

  group('8. cashback', () {
    test('"₹25 cashback credited."', () async {
      final built = await buildAndExtract(
        'Rs.25 cashback credited to your account for your recent purchase.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.cashback);
    });
  });

  group('9. salary', () {
    test('"₹50,000 salary credited."', () async {
      final built = await buildAndExtract(
        'Rs.50,000.00 credited to a/c XX1234 via NEFT. Info: SALARY for July.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.salary);
    });
  });

  group('10. interest', () {
    test('"Interest of ₹145 credited."', () async {
      final built = await buildAndExtract(
        'Interest of Rs.145.32 credited to your savings account for Q2.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.interest);
    });
  });

  group('11. bank fee', () {
    test('"₹500 annual fee debited."', () async {
      final built = await buildAndExtract(
        'Rs.500 annual fee has been debited from your credit card ending 1234.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.fee);
    });
  });

  group('12. loan EMI', () {
    test('"₹8,500 EMI debited."', () async {
      final built = await buildAndExtract(
        'Rs.8,500 debited towards your loan EMI on 15-07-26.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.loanEmi);
      expect(event.moneyMovement.value, isTrue);
    });
  });

  group('13. credit-card purchase', () {
    test('"Your credit card was charged ₹2,500."', () async {
      final built = await buildAndExtract(
        'Your credit card ending 4821 was charged Rs.2,500 at a merchant.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      // Phase 3: CreditCardSemantics now deterministically distinguishes a
      // purchase (charged *to* the card) from a bill payment (paid *toward*
      // the card's balance) — see credit-card-purchase-01/
      // credit-card-bill-payment-01 in the corpus for the full pair.
      expect(event.eventType, FinancialEventType.creditCardPurchase);
      expect(event.paymentMethod.value, PaymentMethod.creditCard);
    });
  });

  group(
    '14. credit-card bill payment (now deterministically distinguished — see CreditCardSemantics)',
    () {
      test('"Credit card payment of ₹5,000 received."', () async {
        final built = await buildAndExtract(
          'Credit card payment of Rs.5,000 received. Thank you.',
        );
        expect(built.item.parsed, isNotNull);
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
        );
        // Phase 3 fix: previously indistinguishable from a generic receipt
        // without AI (a known Phase 2 limitation) — `CreditCardSemantics`
        // now resolves "credit card payment ... received" deterministically
        // to a bill payment, distinct from credit-card-purchase-01 above.
        expect(event.moneyMovement.value, isTrue);
        expect(event.eventType, FinancialEventType.creditCardBill);
        expect(event.role, FinancialEventRole.linkedSettlement);
      });
    },
  );

  group('15. recharge', () {
    test('"₹199 debited for mobile recharge."', () async {
      final built = await buildAndExtract(
        'Rs.199 debited for mobile recharge on 15-07-26.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.recharge);
    });
  });

  group('16. bill payment', () {
    test('"₹2,000 bill payment successful."', () async {
      final built = await buildAndExtract(
        'Rs.2,000 bill payment successful for your electricity connection.',
      );
      expect(built.item.parsed, isNotNull);
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.eventType, FinancialEventType.billPayment);
    });

    test(
      '"Your bill of ₹2,000 is due tomorrow." is a reminder, not a bill payment',
      () async {
        final built = await buildAndExtract(
          'Your bill of Rs.2,000 is due tomorrow. Please pay before the due date.',
        );
        if (built.item.parsed != null) {
          final event = await extractor.extract(
            item: built.item,
            accountMatch: resolvedAccount,
            categories: const [],
          );
          expect(event.moneyMovement.value, isFalse);
        }
      },
    );
  });

  group('17. transfer between own accounts', () {
    Account account(String id, String last4) => Account(
      id: id,
      name: 'Account $id',
      type: AccountType.bank,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF000000,
      createdAt: DateTime(2026, 1, 1),
      accountNumberLast4: last4,
    );

    test(
      'a transfer whose destination last-4 matches another of the user\'s own accounts is flagged',
      () async {
        final built = await buildAndExtract(
          'Rs.5,000 transferred to A/c 9876 via NEFT from a/c XX1234.',
        );
        expect(built.item.parsed, isNotNull);
        final matcher = AccountCardMatcher(
          accounts: [account('acc-1', '1234'), account('acc-2', '9876')],
          cards: const [],
        );
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
          accountCardMatcher: matcher,
        );
        expect(event.isOwnAccountTransfer, isTrue);
      },
    );

    test(
      'a transfer to an unrecognized destination is not flagged as own-account',
      () async {
        final built = await buildAndExtract(
          'Rs.5,000 transferred to A/c 9876 via NEFT from a/c XX1234.',
        );
        final matcher = AccountCardMatcher(
          accounts: [account('acc-1', '1234')],
          cards: const [],
        );
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
          accountCardMatcher: matcher,
        );
        expect(event.isOwnAccountTransfer, isFalse);
      },
    );
  });

  group('18. non-financial SMS', () {
    const nonFinancial = [
      'Your OTP for login is 482913. Do not share with anyone.',
      'Flat 50% off on your next order! Shop now.',
      'Your order has been shipped and is out for delivery.',
      'Recharge now and get cashback offers on your next recharge!',
    ];

    for (final body in nonFinancial) {
      test('"$body" never reaches the financial event pipeline', () async {
        final built = await buildAndExtract(body);
        expect(
          built.passedFilter,
          isFalse,
          reason:
              'must be rejected by the candidate filter before any parsing/AI call',
        );
      });
    }
  });

  group('edge cases', () {
    test('missing reference number does not prevent classification', () async {
      final built = await buildAndExtract(
        'Rs.500 debited from a/c XX1234 to Swiggy on 15-07-26.',
      );
      final event = await extractor.extract(
        item: built.item,
        accountMatch: resolvedAccount,
        categories: const [],
      );
      expect(event.referenceNumber, isNull);
      expect(event.amount.value, 500.0);
    });

    test(
      'missing merchant does not prevent classification, and is never invented',
      () async {
        final built = await buildAndExtract(
          'Rs.500 debited from a/c XX1234 on 15-07-26.',
        );
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
        );
        expect(event.merchant.value, isNull);
      },
    );

    test(
      'an unknown UPI VPA stays a VPA — never inflated into a business name without AI evidence',
      () async {
        final built = await buildAndExtract(
          'Rs.350 sent to 9876543210@oksbi via UPI.',
        );
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
        );
        expect(event.merchant.value, '9876543210@oksbi');
      },
    );

    test(
      'multiple amounts (balance + debit) — the transacted amount wins, not the balance',
      () async {
        final built = await buildAndExtract(
          'Avl Bal Rs.45,230.00. Rs.500.00 debited from a/c XX1234 on 15-07-26.',
        );
        final event = await extractor.extract(
          item: built.item,
          accountMatch: resolvedAccount,
          categories: const [],
        );
        expect(event.amount.value, 500.0);
      },
    );
  });
}
