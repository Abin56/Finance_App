import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_ai_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Always returns whatever was constructed with — a scripted test double,
/// never a real network call (`FinancialEventAiProvider.classify` must
/// never throw; this fake simply hands back a fixed answer).
class _FakeAiProvider implements FinancialEventAiProvider {
  const _FakeAiProvider(this._result);

  final FinancialEventAiResult? _result;

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async => _result;
}

void main() {
  SmsInboxItem buildItem({
    double amount = 500,
    SmsTransactionDirection direction = SmsTransactionDirection.debit,
    String? merchant,
    String? referenceNumber = 'REF123456',
  }) {
    final parsed = ParsedSmsTransaction(
      amount: amount,
      direction: direction,
      dateTime: DateTime(2026, 7, 15),
      category: SmsTransactionCategory.upiPayment,
      confidence: 0.85,
      rawBody:
          'Rs.$amount debited from a/c XX1234 to $merchant on 15-07-26. Ref $referenceNumber',
      merchantOrSender: merchant,
      bankName: 'HDFC Bank',
      maskedAccountOrCard: '1234',
      referenceNumber: referenceNumber,
    );
    return SmsInboxItem(
      id: 'sms-1',
      messageKey: 'key-1',
      rawMessage: RawSmsMessage(
        address: 'VM-HDFCBK',
        body: parsed.rawBody,
        date: DateTime(2026, 7, 15),
      ),
      dedupKey: 'dedup-1',
      status: SmsImportStatus.pending,
      createdAt: DateTime(2026, 7, 15),
      parsed: parsed,
    );
  }

  const resolvedAccount = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    bankConfirmed: true,
    matchReason: 'Matched HDFC Bank ••••1234 by last-4 and bank.',
  );

  FinancialEventAiResult aiResult({
    double? amount,
    String? direction,
    String? merchant,
    String? evidenceMerchant,
  }) {
    return FinancialEventAiResult(
      eventType: 'payment',
      direction: direction,
      amount: amount,
      merchant: merchant,
      category: null,
      paymentMethod: 'upi',
      role: 'standalone',
      isLikelyRefundOrReversal: false,
      confidences: const FinancialEventAiFieldConfidences(
        eventType: 0.8,
        direction: 0.8,
        amount: 0.8,
        merchant: 0.8,
        category: 0.0,
      ),
      evidenceMerchant: evidenceMerchant,
    );
  }

  test(
    'regex-only mode (no AI provider) uses the parser evidence at its own confidence',
    () async {
      const extractor = FinancialEventExtractor();
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(event.amount.value, 500);
      expect(event.amount.source, EvidenceSource.regexOnly);
      expect(event.amount.confidence, 0.85);
      expect(event.needsReview, isFalse);
    },
  );

  test(
    'AI abstaining (classify returns null) behaves identically to no provider configured',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: const _FakeAiProvider(null),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(event.amount.source, EvidenceSource.regexOnly);
      expect(event.needsReview, isFalse);
    },
  );

  test(
    'regex and AI agreeing on amount boosts confidence above the parser baseline',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: _FakeAiProvider(aiResult(amount: 500)),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(event.amount.source, EvidenceSource.bothAgree);
      expect(event.amount.confidence, greaterThan(0.85));
      expect(event.needsReview, isFalse);
    },
  );

  test(
    'regex and AI disagreeing on amount: regex wins, confidence capped, and the conflict is flagged',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: _FakeAiProvider(aiResult(amount: 5000)),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(
        event.amount.value,
        500,
        reason: 'regex is the hard-fact source of truth on amount',
      );
      expect(event.amount.source, EvidenceSource.bothDisagree);
      expect(event.amount.confidence, lessThanOrEqualTo(0.4));
      expect(event.needsReview, isTrue);
      expect(event.reviewReasons, isNotEmpty);
      expect(event.reviewReasons.first, contains('₹500.00'));
      expect(event.reviewReasons.first, contains('₹5000.00'));
    },
  );

  test(
    'regex and AI disagreeing on direction: regex wins but the conflict is flagged',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: _FakeAiProvider(aiResult(amount: 500, direction: 'credit')),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(event.direction, SmsTransactionDirection.debit);
      expect(event.needsReview, isTrue);
    },
  );

  test(
    'an AI merchant guess with no quoted evidence is ignored entirely',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: _FakeAiProvider(
          aiResult(
            amount: 500,
            merchant: 'Some Guessed Merchant',
            evidenceMerchant: null,
          ),
        ),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(
        event.merchant.value,
        'Swiggy',
        reason:
            'unevidenced AI merchant must never override a real regex value',
      );
    },
  );

  test(
    'merchant disagreement: AI wins when the regex guess is a bare UPI VPA',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: _FakeAiProvider(
          aiResult(
            amount: 500,
            merchant: 'Swiggy',
            // Grounded (Phase 4): quotes the VPA text that actually occurs
            // in the message (see buildItem's rawBody), rather than a
            // phrase invented wholesale — see EvidenceGrounding.
            evidenceMerchant: 'to 9876543210@oksbi',
          ),
        ),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: '9876543210@oksbi'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(event.merchant.value, 'Swiggy');
      expect(event.merchant.source, EvidenceSource.bothDisagree);
      expect(event.needsReview, isTrue);
    },
  );

  test(
    'merchant disagreement: a confident regex name wins over an unrelated AI guess',
    () async {
      final extractor = FinancialEventExtractor(
        aiProvider: _FakeAiProvider(
          aiResult(
            amount: 500,
            merchant: 'Zomato',
            evidenceMerchant: 'at Zomato',
          ),
        ),
      );
      final event = await extractor.extract(
        item: buildItem(merchant: 'Swiggy'),
        accountMatch: resolvedAccount,
        categories: const [],
      );

      expect(event.merchant.value, 'Swiggy');
      expect(event.needsReview, isTrue);
    },
  );

  test('an unresolved account is recorded as a review reason', () async {
    const extractor = FinancialEventExtractor();
    const unresolved = AccountMatchResult.unresolved(
      reason: 'No matching account or card found for this message.',
    );
    final event = await extractor.extract(
      item: buildItem(merchant: 'Swiggy'),
      accountMatch: unresolved,
      categories: const [],
    );

    expect(event.accountMatch.value, isNull);
    expect(event.reviewReasons, contains(unresolved.matchReason));
  });
}
