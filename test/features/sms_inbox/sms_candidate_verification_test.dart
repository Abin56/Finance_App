import 'package:finance_app/features/sms_inbox/domain/sms_candidate_verification.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_direction_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_event_class.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_regex_utils.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_date_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

const _debit = SmsTransactionDirection.debit;
const _credit = SmsTransactionDirection.credit;

final _received = DateTime(2026, 11, 1, 23, 16);

SmsCandidateVerification _verify(
  String body, {
  SmsTransactionDirection? parsedDirection,
  bool accountResolved = true,
  String? matchedCardId,
  DateTime? receivedAt,
}) {
  return SmsCandidateVerifier.verify(
    body: body,
    receivedAt: receivedAt ?? _received,
    // By default the parser stored exactly what it would store today.
    parsedDirection:
        parsedDirection ?? SmsRegexUtils.extractDirection(body) ?? _debit,
    accountResolved: accountResolved,
    matchedCardId: matchedCardId,
  );
}

void main() {
  group('SmsDirectionResolver — direction from the whole message', () {
    void expectDirection(
      String body,
      SmsTransactionDirection? direction, {
      DirectionEvidence? evidence = DirectionEvidence.contextual,
    }) {
      final verdict = SmsDirectionResolver.resolve(body);
      expect(verdict.direction, direction, reason: body);
      if (direction != null) expect(verdict.evidence, evidence, reason: body);
    }

    test('BOI "debited A/cXX9585 and credited to NAME" is the user\'s debit', () {
      expectDirection(
        'Rs.350.00 debited A/cXX9585 and credited to ABIN  JOHN via UPI Ref No 630557620611 on 01Nov26. Call 18001031906, if not done by you. -BOI',
        _debit,
      );
    });

    test('"credited to NAME" alone means the user paid NAME', () {
      expectDirection('Rs.500 credited to RAHUL SHARMA via UPI.', _debit);
    });

    test('"debited from VPA x@y" means the user received', () {
      expectDirection(
        'Your a/c XX1234 is credited with Rs.500; debited from VPA rahul@oksbi.',
        _credit,
      );
    });

    test('common Indian bank formats', () {
      expectDirection(
        'Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 01Nov26 by (Ref no 123456)',
        _credit,
      );
      expectDirection(
        'Money Received - INR 500.00 in your HDFC Bank A/c xx1234 on 01-11-26 by A/c linked to VPA x@y (UPI Ref No 123456).',
        _credit,
      );
      expectDirection(
        'Sent Rs.500.00 From HDFC Bank A/C x1234 To ABC On 01/11/26 Ref 123456',
        _debit,
      );
      expectDirection(
        'ICICI Bank Acct XX123 debited for Rs 500.00 on 01-Nov-26; ABC credited. UPI:123456.',
        _debit,
      );
      expectDirection(
        'Received Rs.500.00 in your Kotak Bank AC X1234 from abc@ybl on 01-11-26.',
        _credit,
      );
      expectDirection('Rs.899.99 spent on card XX2222 at STORE.', _debit);
      expectDirection(
        'Rs.500.00 reversed and credited back to your HDFC Bank Debit Card XX1234 account.',
        _credit,
      );
    });

    test('a self-transfer naming two accounts is unknown, not guessed', () {
      expectDirection(
        'Rs 500 debited from a/c XX1111 and credited to a/c XX2222.',
        null,
      );
    });

    test('a payment to someone else\'s named account is still a debit', () {
      expectDirection(
        'Rs.500 debited from your a/c XX1111 and credited to a/c XX2222 of RAMESH KUMAR.',
        _debit,
      );
    });

    test(
      'status-only wording is never direction evidence (no debit default)',
      () {
        for (final body in [
          'Payment of Rs.500 successful.',
          'Your transaction of Rs.500 is completed.',
          'Rs.500 transaction processed.',
          'Your payment of Rs.500 failed.',
          'Your payment of Rs.500 is pending.',
        ]) {
          expect(
            SmsDirectionResolver.resolve(body).isKnown,
            isFalse,
            reason: body,
          );
        }
      },
    );

    test('"transaction" is no longer a debit word', () {
      expectDirection(
        'Rs.5,000 credit card transaction has been reversed.',
        _credit,
        evidence: DirectionEvidence.keyword,
      );
    });

    test('bare verbs only → keyword evidence', () {
      expectDirection(
        'INR 500 charged at STORE.',
        _debit,
        evidence: DirectionEvidence.keyword,
      );
    });

    test(
      'the parser keeps a PROVISIONAL direction so unclear messages still parse',
      () {
        expect(
          SmsRegexUtils.extractDirection('Payment of Rs.500 successful.'),
          _debit,
        );
      },
    );
  });

  group('SmsCandidateVerifier — event class', () {
    void expectClass(
      String body,
      SmsEventClass expected, {
      String? matchedCardId,
    }) {
      final v = _verify(body, matchedCardId: matchedCardId);
      expect(v.eventClass, expected, reason: body);
      expect(v.moneyMovement, expected.movesMoney, reason: body);
    }

    test('actual debit and actual credit', () {
      expectClass(
        'Rs.350.00 debited A/cXX9585 and credited to ABIN  JOHN via UPI Ref No 630557620611 on 01Nov26. -BOI',
        SmsEventClass.actualDebit,
      );
      expectClass(
        'Rs.500 credited to your a/c XX1234 from RAHUL on 01-11-26.',
        SmsEventClass.actualCredit,
      );
    });

    test('failed — never a money movement', () {
      expectClass(
        'Your UPI payment of Rs.500 to ABC has failed.',
        SmsEventClass.failedTransaction,
      );
      expectClass(
        'Rs.500 debited from a/c XX1234 has failed.',
        SmsEventClass.failedTransaction,
      );
      expectClass(
        'Transaction of Rs.500 declined due to insufficient balance.',
        SmsEventClass.failedTransaction,
      );
    });

    test('pending — not completed', () {
      expectClass(
        'Your payment of Rs.500 is pending confirmation.',
        SmsEventClass.pendingTransaction,
      );
    });

    test('a completed debit mentioning "processing fee" is not pending', () {
      expectClass(
        'Rs.500 debited from your a/c XX1234 towards processing fee.',
        SmsEventClass.actualDebit,
      );
    });

    test('scheduled / reminders — no money moved', () {
      expectClass(
        'Rs.5,000 will be debited from your a/c XX1234 on 05-Nov-26 towards EMI.',
        SmsEventClass.emiReminder,
      );
      expectClass(
        'Your bill of Rs.999 is due on 15-Nov-26. Please pay to avoid late fee.',
        SmsEventClass.scheduledDebit,
      );
      expectClass(
        'Rs.500 will be credited to your a/c XX1234 by 05-Nov-26.',
        SmsEventClass.scheduledCredit,
      );
    });

    test('EMI debited', () {
      expectClass(
        'EMI of Rs.5,000 debited from your a/c XX1234 for loan 123.',
        SmsEventClass.emiDebited,
      );
    });

    test('reversal and credit card refund', () {
      expectClass(
        'Rs.500 reversed and credited to your a/c XX1234.',
        SmsEventClass.reversal,
      );
      expectClass(
        'Refund of Rs.500 credited to your credit card XX1234.',
        SmsEventClass.creditCardRefund,
      );
    });

    test('credit card purchase, bill payment and bill due', () {
      expectClass(
        'Rs.1,200 spent on your ICICI Bank Credit Card XX4321 at AMAZON on 01-Nov-26.',
        SmsEventClass.creditCardPurchase,
      );
      expectClass(
        'Payment of Rs.10,000 received towards your credit card XX4321. Thank you.',
        SmsEventClass.cardBillPayment,
      );
      // A bill reminder is NOT a payment.
      expectClass(
        'Your credit card XX4321 statement: Total Amount Due Rs.12,000, Minimum Amount Due Rs.600, due by 20-Nov-26.',
        SmsEventClass.scheduledDebit,
      );
      // A debit on a matched card is a card purchase, not a bank debit.
      expectClass(
        'Rs.700 debited on card XX4321 at STORE.',
        SmsEventClass.creditCardPurchase,
        matchedCardId: 'card-1',
      );
    });

    test(
      'a real purchase that also states the due amount is still a purchase',
      () {
        expectClass(
          'Rs.500 spent on card XX4321 at STORE. Total amt due Rs.5,000 by 15 Nov.',
          SmsEventClass.actualDebit,
        );
      },
    );

    test('balance and limit alerts', () {
      expectClass(
        'Avl bal in your a/c XX1234 is Rs.5,000 as on 01-Nov-26.',
        SmsEventClass.balanceAlert,
      );
      expectClass(
        'Available credit limit on your card XX4321 is Rs.45,000.',
        SmsEventClass.balanceAlert,
      );
    });

    test('EMI conversion notice is informational', () {
      expectClass(
        'Your transaction of Rs.20,000 on card XX4321 has been converted to EMI.',
        SmsEventClass.informational,
      );
    });

    test('third-party account and money requests', () {
      expectClass(
        'Rs.500 credited to a/c XX2222 of RAMESH KUMAR.',
        SmsEventClass.thirdPartyEvent,
      );
      expectClass(
        'RAMESH has requested Rs.500 from you via UPI. Ignore if not known.',
        SmsEventClass.informational,
      );
      // The user's own payment INTO someone else's account is theirs.
      expectClass(
        'Rs.500 debited from your a/c XX1111 and credited to a/c XX2222 of RAMESH KUMAR.',
        SmsEventClass.actualDebit,
      );
    });

    test('unclear direction → unknown, not uploadable', () {
      final v = _verify('Payment of Rs.500 successful.');
      expect(v.eventClass, SmsEventClass.unknown);
      expect(v.directionMatchesParse, isFalse);
      expect(v.uploadable, isFalse);
      expect(v.cleanForImport, isFalse);
    });
  });

  group('SmsCandidateVerifier — mandatory checks', () {
    const boi =
        'Rs.350.00 debited A/cXX9585 and credited to ABIN  JOHN via UPI Ref No 630557620611 on 01Nov26. -BOI';

    test('verified debit with a matched account is clean for import', () {
      final v = _verify(boi);
      expect(v.ownership, SmsOwnership.verified);
      expect(v.reasons, isEmpty);
      expect(v.cleanForImport, isTrue);
      expect(v.uploadable, isTrue);
    });

    test('ownership is never assumed: no account match → not clean', () {
      final v = _verify(boi, accountResolved: false);
      expect(v.ownership, SmsOwnership.unverified);
      expect(v.cleanForImport, isFalse);
    });

    test('a stored direction that disagrees with the message is unclear', () {
      final v = _verify(boi, parsedDirection: _credit);
      expect(v.directionMatchesParse, isFalse);
      expect(v.uploadable, isFalse);
      expect(v.reasons, isNotEmpty);
    });

    test('keyword-only direction is importable but needs review', () {
      final v = _verify('INR 500 charged at STORE.');
      expect(v.uploadable, isTrue);
      expect(v.cleanForImport, isFalse);
    });

    test('refunds, reversals and card bill payments always need review', () {
      for (final body in [
        'Rs.500 reversed and credited to your a/c XX1234.',
        'Payment of Rs.10,000 received towards your credit card XX4321.',
      ]) {
        final v = _verify(body);
        expect(v.moneyMovement, isTrue, reason: body);
        expect(v.cleanForImport, isFalse, reason: body);
      }
    });

    test('a credit card purchase matched to a non-card account is flagged', () {
      final v = _verify(
        'Rs.1,200 spent on your ICICI Bank Credit Card XX4321 at AMAZON.',
      );
      expect(v.eventClass, SmsEventClass.creditCardPurchase);
      expect(v.cleanForImport, isFalse);
      expect(
        _verify(
          'Rs.1,200 spent on your ICICI Bank Credit Card XX4321 at AMAZON.',
          matchedCardId: 'card-1',
        ).cleanForImport,
        isTrue,
      );
    });
  });

  group('Android ↔ Web contract (eventClass)', () {
    // These literals are mirrored exactly in FlowFi Web:
    // `SMS_CANDIDATE_EVENT_CLASSES`, and MONEY_MOVING / ROUTINE in
    // features/transaction-candidates/lib/candidate-event-class.ts. Changing
    // one side without the other breaks import safety — update both.
    test('the serialized names are exactly the web\'s', () {
      expect(SmsEventClass.values.map((e) => e.name).toList(), [
        'actualCredit',
        'actualDebit',
        'scheduledCredit',
        'scheduledDebit',
        'creditCardPurchase',
        'creditCardRefund',
        'cardBillPayment',
        'emiReminder',
        'emiDebited',
        'failedTransaction',
        'pendingTransaction',
        'reversal',
        'balanceAlert',
        'thirdPartyEvent',
        'informational',
        'unknown',
      ]);
    });

    test('money-moving and routine sets match the web', () {
      expect(
        SmsEventClass.values.where((e) => e.movesMoney).map((e) => e.name),
        unorderedEquals([
          'actualCredit',
          'actualDebit',
          'creditCardPurchase',
          'creditCardRefund',
          'cardBillPayment',
          'emiDebited',
          'reversal',
        ]),
      );
      expect(
        SmsEventClass.values.where((e) => e.isRoutine).map((e) => e.name),
        unorderedEquals([
          'actualCredit',
          'actualDebit',
          'creditCardPurchase',
          'emiDebited',
        ]),
      );
    });

    test('an unrecognised name reads as unknown (never importable)', () {
      expect(SmsEventClassX.fromName('somethingNew'), SmsEventClass.unknown);
      expect(SmsEventClass.unknown.movesMoney, isFalse);
      expect(SmsEventClassX.fromName(null), isNull);
    });
  });

  group('SmsTransactionDateExtractor', () {
    SmsTransactionDate extract(String body, DateTime received) =>
        SmsTransactionDateExtractor.extract(body, received);

    test('a body date on another day is used, at midday', () {
      final d = extract(
        'Rs.500 debited from a/c XX1234 on 01Nov26.',
        DateTime(2026, 11, 3, 9, 30),
      );
      expect(d.dateTime, DateTime(2026, 11, 1, 12));
      expect(d.source, SmsDateSource.messageBody);
    });

    test('a body date on the received day keeps the received time', () {
      final received = DateTime(2026, 11, 1, 23, 16);
      final d = extract('Rs.500 debited on 01-11-2026.', received);
      expect(d.dateTime, received);
      expect(d.source, SmsDateSource.messageBody);
    });

    test('day-first numeric, month names and ISO are read', () {
      final received = DateTime(2026, 7, 20, 10);
      expect(
        extract('debited on 15-07-26', received).dateTime,
        DateTime(2026, 7, 15, 12),
      );
      expect(
        extract('debited on 15/07/2026', received).dateTime,
        DateTime(2026, 7, 15, 12),
      );
      expect(
        extract('debited on 15 Jul 2026', received).dateTime,
        DateTime(2026, 7, 15, 12),
      );
      expect(
        extract('debited on 2026-07-15', received).dateTime,
        DateTime(2026, 7, 15, 12),
      );
    });

    test('unreliable dates fall back to the received time', () {
      final received = DateTime(2026, 11, 3, 9, 30);
      for (final body in [
        'debited on 01Jan25', // far outside the window
        'debited on 10-12-26', // in the future
        'debited on 31-02-26', // not a real date
        'Spent 01-11-26, due 20-11-26', // two dates, neither after "on"
        'Rs.500 debited. Call 18001031906.', // no date at all
      ]) {
        final d = extract(body, received);
        expect(d.dateTime, received, reason: body);
        expect(d.source, SmsDateSource.messageReceived, reason: body);
      }
    });

    test('amounts, phone numbers and reference numbers are not dates', () {
      final received = DateTime(2026, 11, 3, 9, 30);
      final d = extract(
        'Rs.1,250.00 debited. Ref 630557620611. Call 1800-103-1906.',
        received,
      );
      expect(d.source, SmsDateSource.messageReceived);
    });
  });
}
