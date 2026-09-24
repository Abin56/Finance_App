import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/category_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_ai_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Part 9 (person vs. business / `merchantType`) and Part 10 (adversarial
/// AI-hallucination resistance) of the SMS semantic evaluation corpus need a
/// scripted AI provider to mean anything — the regex-only corpus harness
/// (`sms_corpus_evaluation_test.dart`) can never produce
/// `MerchantType.person` at all (that value is only ever reachable via AI,
/// see `MerchantIdentityResolver`), and "does the pipeline resist a
/// hallucinating AI" is not a question the deterministic layer alone can
/// answer. This file exercises the real `FinancialEventExtractor` end to
/// end with a scripted [FinancialEventAiProvider], exactly like
/// `financial_event_extractor_ai_selectivity_test.dart` does for AI-call
/// selectivity — no production code is touched here, only evaluated.
class _ScriptedAiProvider implements FinancialEventAiProvider {
  _ScriptedAiProvider(this._result);

  final FinancialEventAiResult? _result;

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async => _result;
}

void main() {
  const resolvedAccount = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    matchReason: 'Matched by last-4.',
  );

  Future<SmsInboxItem> buildItem(
    String body, {
    String sender = 'VM-HDFCBK',
  }) async {
    final message = RawSmsMessage(
      address: sender,
      body: body,
      date: DateTime(2026, 7, 15, 10),
    );
    final parsed = SmsFinancialFilter.isFinancial(message)
        ? const SmsParserRegistry().tryParse(message)
        : null;
    return SmsInboxItem(
      id: 'sms-1',
      messageKey: 'key-1',
      rawMessage: message,
      dedupKey: 'dedup-1',
      status: SmsImportStatus.pending,
      createdAt: DateTime(2026, 7, 15),
      parsed: parsed,
    );
  }

  group('Part 10 — adversarial AI-hallucination resistance', () {
    test(
      'a bare, uncatalogued VPA stays unknown when the AI supplies a merchant guess with NO evidence at all',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: 'Rahul',
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.9,
              category: 0.0,
            ),
            evidenceMerchant: null,
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem(
          'Rs.500 paid to 9876543210@oksbi via UPI.',
        );
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(
          event.merchant.value,
          '9876543210@oksbi',
          reason:
              'unevidenced AI merchant guess must be treated exactly like "AI had no opinion"',
        );
        expect(event.merchantType.value, isNull);
      },
    );

    test(
      'FIXED (Phase 4) — part A: invented merchant evidence that never occurs in the message is rejected, '
      'even though it is a non-empty, plausible-sounding string',
      () async {
        // The message never mentions "Rahul" or any name at all — the AI's
        // claimed evidence below is entirely invented. Before Phase 4, a
        // non-empty evidence string was the only check performed
        // (`MerchantResolver`/`MerchantIdentityResolver.resolveWithAi`);
        // now `EvidenceGrounding` also verifies the quote is a genuine
        // (normalized) substring of the message it supposedly came from.
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: 'Rahul',
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.9,
              category: 0.0,
            ),
            merchantType: 'person',
            evidenceMerchant: 'paid to Rahul',
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem('Rs.500 paid to xyz@upi.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(
          event.merchant.value,
          isNot('Rahul'),
          reason: 'a fabricated quote must never become the canonical merchant',
        );
        expect(event.merchantType.value, isNot(MerchantType.person));
        expect(
          event.reviewReasons,
          anyElement(contains('aiEvidenceNotGrounded')),
          reason:
              'the rejection must be recorded for a human reviewer, not silently dropped',
        );
      },
    );

    test(
      'FIXED (Phase 4) — part B (positive control): real merchant evidence that genuinely occurs in the message is accepted',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: 'Rahul',
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.9,
              category: 0.0,
            ),
            merchantType: 'person',
            evidenceMerchant: 'paid to Rahul',
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        // Deliberately a body the deterministic explicit-text tier does
        // NOT already resolve on its own (a masked-account-shaped local
        // part keeps the VPA route from firing first), isolating this as a
        // genuine AI-assisted resolution rather than a deterministic one.
        final item = await buildItem('Rs.500 paid to Rahul.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(event.merchant.value, 'Rahul');
      },
    );

    test(
      'FIXED (Phase 4) — part C: invented category evidence gains no AI confidence when it does not occur in the message',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: null,
            category: 'Food & Dining',
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.0,
              category: 0.9,
            ),
            evidenceCategory: 'restaurant purchase',
          ),
        );
        final foodCategory = Category(
          id: 'cat-food',
          name: 'Food & Dining',
          type: CategoryType.expense,
          iconKey: 'restaurant',
          colorValue: 0xFF000000,
          createdAt: DateTime(2026),
        );
        final extractor = FinancialEventExtractor(
          aiProvider: ai,
          categoryResolver: CategoryResolver(
            const MerchantCategorySuggester([]),
          ),
        );
        final item = await buildItem('Rs.500 paid to xyz@upi.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: [foodCategory],
        );

        expect(
          event.category.value,
          isNull,
          reason:
              'an ungrounded category claim must never resolve the category, even to a category that genuinely exists',
        );
        expect(
          event.reviewReasons,
          anyElement(contains('aiEvidenceNotGrounded')),
        );
      },
    );

    test(
      'FIXED (Phase 4) — part D (positive control): a real, explicit provider phrase resolves paymentProvider',
      () async {
        final extractor = const FinancialEventExtractor();
        final item = await buildItem('Rs.500 paid using PhonePe.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(event.paymentProvider.value, PaymentProvider.phonePe);
      },
    );

    test(
      'FIXED (Phase 4) — part E: an invented provider claim from the AI is ignored when no deterministic signal supports it',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: null,
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.0,
              category: 0.0,
            ),
            paymentProvider: 'phonePe',
            evidenceMerchant: null,
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem('Rs.500 paid to xyz@upi.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(
          event.paymentProvider.value,
          isNull,
          reason:
              'no explicit "using PhonePe" phrase and no known handle hint exist in the message — the AI\'s bare claim must not manufacture a provider out of nothing',
        );
      },
    );

    test(
      'FIXED (Phase 4) — part F: case-insensitive normalization still accepts genuinely grounded evidence',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: 'Rahul',
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.9,
              category: 0.0,
            ),
            merchantType: 'person',
            // Different case than the SMS body below — normalization must
            // still recognize this as the same text.
            evidenceMerchant: 'paid to rahul',
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem('RS.500 PAID TO RAHUL.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(event.merchant.value, 'Rahul');
      },
    );

    test(
      'FIXED (Phase 4) — part G: whitespace-variation normalization still accepts genuinely grounded evidence',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: 'Rahul',
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.9,
              category: 0.0,
            ),
            merchantType: 'person',
            // Single-spaced evidence vs. a multi-spaced body — collapsed
            // whitespace normalization must still match.
            evidenceMerchant: 'paid to Rahul',
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem('Rs.500 paid   to   Rahul.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(event.merchant.value, 'Rahul');
      },
    );

    test(
      'a payment-provider claim from the AI is ignored when the merchant itself has no evidence',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: null,
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.0,
              category: 0.0,
            ),
            // Deliberately contradicts the deterministic handle-hint
            // (@oksbi -> googlePay) to prove the AI's claim never overrides
            // it when it isn't accompanied by a confirmed merchant.
            paymentProvider: 'paytm',
            evidenceMerchant: null,
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem(
          'Rs.500 paid to 9876543210@oksbi via UPI.',
        );
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(
          event.paymentProvider.value,
          PaymentProvider.googlePay,
          reason:
              'the deterministic @oksbi handle hint must win — the AI\'s unconfirmed paytm claim is never allowed to silently override it',
        );
      },
    );
  });

  group('Part 9 — person vs. business (merchantType), with genuine evidence', () {
    test(
      'a genuinely quoted person name from the AI resolves merchantType to person',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 1000,
            merchant: 'Rahul Kumar',
            category: null,
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.9,
              direction: 0.9,
              amount: 0.9,
              merchant: 0.85,
              category: 0.0,
            ),
            merchantType: 'person',
            evidenceMerchant: 'transferred to Rahul Kumar',
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem('Rs.1,000 transferred to Rahul Kumar.');
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        // The deterministic explicit-text tier already resolves "Rahul
        // Kumar" on its own here (a human-shaped name, not a bare VPA), so
        // this exercises the *legitimate* everyday path: the AI's
        // corroborating evidence is exactly what a real "transferred to
        // <name>" SMS provides. This is a positive control for the
        // hallucination tests above.
        expect(event.merchant.value, 'Rahul Kumar');
      },
    );

    test(
      'a known catalog merchant never becomes merchantType.person even if the AI is not consulted',
      () async {
        final extractor = const FinancialEventExtractor();
        final item = await buildItem(
          'Rs.450 debited from a/c XX1234 to Swiggy on 15-07-26.',
        );
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(event.merchant.value, 'Swiggy');
        expect(event.merchantType.value, MerchantType.business);
      },
    );

    test(
      'AI-assisted upgrade from a bare VPA to a real merchant name works when the evidence is a genuine quoted substring',
      () async {
        final ai = _ScriptedAiProvider(
          FinancialEventAiResult(
            eventType: 'payment',
            direction: 'debit',
            amount: 500,
            merchant: 'Cafe Mocha',
            category: 'Food & Dining',
            paymentMethod: 'upi',
            role: 'standalone',
            isLikelyRefundOrReversal: false,
            confidences: const FinancialEventAiFieldConfidences(
              eventType: 0.8,
              direction: 0.8,
              amount: 0.8,
              merchant: 0.75,
              category: 0.6,
            ),
            merchantType: 'business',
            evidenceMerchant: 'at Cafe Mocha',
          ),
        );
        final extractor = FinancialEventExtractor(aiProvider: ai);
        final item = await buildItem(
          'Rs.500 paid to xyz@oksbi at Cafe Mocha via UPI.',
        );
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: const <Category>[],
        );

        expect(
          event.merchant.value,
          'Cafe Mocha',
          reason:
              'a genuinely quoted, present-in-the-message name legitimately upgrades an unresolved VPA',
        );
        expect(event.merchantType.value, MerchantType.business);
      },
    );
  });

  group(
    'Phase 5 — structured evidence type, end to end through the real extractor',
    () {
      test(
        'THE MOTIVATING CASE: a grounded VPA quote tagged evidenceType=vpa does not become an invented merchant, '
        'even though Phase 4 substring grounding alone would have accepted it',
        () async {
          final ai = _ScriptedAiProvider(
            FinancialEventAiResult(
              eventType: 'payment',
              direction: 'debit',
              amount: 500,
              merchant: 'Rahul',
              category: null,
              paymentMethod: 'upi',
              role: 'standalone',
              isLikelyRefundOrReversal: false,
              confidences: const FinancialEventAiFieldConfidences(
                eventType: 0.9,
                direction: 0.9,
                amount: 0.9,
                merchant: 0.9,
                category: 0.0,
              ),
              merchantType: 'person',
              // Genuinely grounded — "abc123@oksbi" really does occur in the
              // message below. Phase 4's plain substring check alone would
              // have accepted this. Tagging it as `vpa` evidence is what
              // Phase 5's AiClaimValidator uses to correctly reject it
              // anyway: a VPA proves the VPA exists, not who it belongs to.
              evidenceMerchant: 'abc123@oksbi',
              evidenceMerchantType: 'vpa',
            ),
          );
          final extractor = FinancialEventExtractor(aiProvider: ai);
          final item = await buildItem('Rs.500 paid to abc123@oksbi.');
          expect(item.parsed, isNotNull);

          final event = await extractor.extract(
            item: item,
            accountMatch: resolvedAccount,
            categories: const <Category>[],
          );

          expect(
            event.merchant.value,
            isNot('Rahul'),
            reason: 'evidenceType=vpa must never be accepted as identity proof',
          );
          expect(event.merchantType.value, isNot(MerchantType.person));
        },
      );

      test(
        'a category claim backed only by a provider-name quote is rejected even when genuinely grounded',
        () async {
          final ai = _ScriptedAiProvider(
            FinancialEventAiResult(
              eventType: 'payment',
              direction: 'debit',
              amount: 500,
              merchant: null,
              category: 'Shopping',
              paymentMethod: 'upi',
              role: 'standalone',
              isLikelyRefundOrReversal: false,
              confidences: const FinancialEventAiFieldConfidences(
                eventType: 0.9,
                direction: 0.9,
                amount: 0.9,
                merchant: 0.0,
                category: 0.9,
              ),
              evidenceCategory: 'using PhonePe',
              evidenceCategoryType: 'provider_name',
            ),
          );
          final shoppingCategory = Category(
            id: 'cat-shopping',
            name: 'Shopping',
            type: CategoryType.expense,
            iconKey: 'shopping_bag',
            colorValue: 0xFF000000,
            createdAt: DateTime(2026),
          );
          final extractor = FinancialEventExtractor(
            aiProvider: ai,
            categoryResolver: CategoryResolver(
              const MerchantCategorySuggester([]),
            ),
          );
          final item = await buildItem('Rs.500 paid using PhonePe.');
          expect(item.parsed, isNotNull);

          final event = await extractor.extract(
            item: item,
            accountMatch: resolvedAccount,
            categories: [shoppingCategory],
          );

          expect(
            event.category.value,
            isNull,
            reason:
                'a payment rail/provider is never a spending category, even when genuinely quoted',
          );
        },
      );
    },
  );
}
