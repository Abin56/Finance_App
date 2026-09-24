import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/category_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_ai_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_identity_cache.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records how many times [classify] was actually invoked — the whole point
/// of `AiCallNecessity`: a known merchant/category/unambiguous message
/// should never trigger this at all.
class _CountingAiProvider implements FinancialEventAiProvider {
  int callCount = 0;
  FinancialEventAiResult? Function(FinancialEventAiRequest)? onCall;

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async {
    callCount++;
    return onCall?.call(request);
  }
}

void main() {
  const resolvedAccount = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    matchReason: 'Matched by last-4.',
  );

  Category category(String id, String name) => Category(
    id: id,
    name: name,
    type: CategoryType.expense,
    iconKey: 'shopping',
    colorValue: 0xFF000000,
    createdAt: DateTime(2026),
  );
  final foodCategory = category('cat-food', 'Food & Dining');
  final categories = [foodCategory];
  final categoryResolver = CategoryResolver(
    const MerchantCategorySuggester([]),
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

  group(
    'AI selectivity — known merchant + known category + unambiguous -> AI is never called',
    () {
      test(
        'a known-VPA Swiggy payment with a resolvable category skips AI entirely',
        () async {
          final provider = _CountingAiProvider();
          final extractor = FinancialEventExtractor(
            aiProvider: provider,
            categoryResolver: categoryResolver,
          );
          final item = await buildItem(
            'Rs.450 paid to swiggy@icici via UPI. UPI Ref 123456789012.',
          );
          expect(item.parsed, isNotNull);

          final event = await extractor.extract(
            item: item,
            accountMatch: resolvedAccount,
            categories: categories,
          );

          expect(
            provider.callCount,
            0,
            reason:
                'merchant known via VPA catalog, category known via seed catalog, no ambiguity',
          );
          expect(
            event.merchant.value,
            'Swiggy',
            reason:
                'catalog normalization must still apply even without an AI call',
          );
          expect(event.category.value, 'cat-food');
        },
      );
    },
  );

  group('AI selectivity — AI IS called when a signal is missing or ambiguous', () {
    test('an unresolved merchant triggers an AI call', () async {
      final provider = _CountingAiProvider()..onCall = (_) => null;
      final extractor = FinancialEventExtractor(
        aiProvider: provider,
        categoryResolver: categoryResolver,
      );
      final item = await buildItem('Rs.500 paid to 9876543210@oksbi via UPI.');
      expect(item.parsed, isNotNull);

      await extractor.extract(
        item: item,
        accountMatch: resolvedAccount,
        categories: categories,
      );

      expect(provider.callCount, 1);
    });

    test(
      'an unresolvable category (unknown merchant, no seed match) triggers an AI call',
      () async {
        final provider = _CountingAiProvider()..onCall = (_) => null;
        final extractor = FinancialEventExtractor(
          aiProvider: provider,
          categoryResolver: categoryResolver,
        );
        final item = await buildItem(
          'Rs.500 debited from a/c XX1234 to ABC Store.',
        );
        expect(item.parsed, isNotNull);

        await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: categories,
        );

        expect(provider.callCount, 1);
      },
    );

    test(
      'ambiguous credit-card wording triggers an AI call even with a known merchant',
      () async {
        final provider = _CountingAiProvider()..onCall = (_) => null;
        final extractor = FinancialEventExtractor(
          aiProvider: provider,
          categoryResolver: categoryResolver,
        );
        final item = await buildItem(
          'Rs.500 credit card transaction with swiggy@icici via UPI.',
        );
        expect(item.parsed, isNotNull);

        await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: categories,
        );

        expect(provider.callCount, 1);
      },
    );

    test('a compound debit+reversal message triggers an AI call', () async {
      final provider = _CountingAiProvider()..onCall = (_) => null;
      final extractor = FinancialEventExtractor(
        aiProvider: provider,
        categoryResolver: categoryResolver,
      );
      final item = await buildItem(
        'Rs.5,000 was debited from your account and reversed shortly after.',
      );
      expect(item.parsed, isNotNull);

      final event = await extractor.extract(
        item: item,
        accountMatch: resolvedAccount,
        categories: categories,
      );

      expect(provider.callCount, 1);
      expect(event.needsReview, isTrue);
      expect(event.reviewReasons, isNotEmpty);
      expect(event.reviewReasons.first, contains('net effect'));
    });
  });

  group(
    'MerchantIdentityCache — avoids repeat AI calls for the same unknown merchant within one scan',
    () {
      test(
        'two SMS from the same unresolved VPA only trigger one AI call',
        () async {
          final provider = _CountingAiProvider()
            ..onCall = (request) => FinancialEventAiResult(
              eventType: 'payment',
              direction: request.regexDirection,
              amount: request.regexAmount,
              merchant: 'Local Kirana Store',
              category: null,
              paymentMethod: 'upi',
              role: 'standalone',
              isLikelyRefundOrReversal: false,
              confidences: const FinancialEventAiFieldConfidences(
                eventType: 0.7,
                direction: 0.7,
                amount: 0.7,
                merchant: 0.7,
                category: 0.0,
              ),
              // Grounded (Phase 4): quotes the VPA text that actually
              // occurs in the message, rather than a phrase invented
              // wholesale — see EvidenceGrounding.
              evidenceMerchant: 'paid to 9876543210@oksbi',
            );
          final cache = MerchantIdentityCache();
          final extractor = FinancialEventExtractor(
            aiProvider: provider,
            categoryResolver: categoryResolver,
            merchantIdentityCache: cache,
          );

          final first = await buildItem(
            'Rs.200 paid to 9876543210@oksbi via UPI.',
          );
          final firstEvent = await extractor.extract(
            item: first,
            accountMatch: resolvedAccount,
            categories: categories,
          );
          expect(provider.callCount, 1);
          expect(firstEvent.merchant.value, 'Local Kirana Store');

          final second = await buildItem(
            'Rs.150 paid to 9876543210@oksbi via UPI.',
          );
          final secondEvent = await extractor.extract(
            item: second,
            accountMatch: resolvedAccount,
            categories: categories,
          );

          // The merchant is now known (cached from the first call) — the second
          // message never needs its own AI call, even though everything else
          // about it is a fresh SMS.
          expect(
            provider.callCount,
            1,
            reason:
                'the cached identity from the first SMS answers the second one too',
          );
          expect(secondEvent.merchant.value, 'Local Kirana Store');
        },
      );
    },
  );

  group('paymentProvider / merchantType end-to-end', () {
    test(
      'a PhonePe payment to a known merchant sets paymentProvider without needing AI',
      () async {
        final provider = _CountingAiProvider();
        final extractor = FinancialEventExtractor(
          aiProvider: provider,
          categoryResolver: categoryResolver,
        );
        final item = await buildItem(
          'Paid Rs.450 using PhonePe to swiggy@icici via UPI.',
        );
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: categories,
        );

        expect(event.paymentProvider.value, PaymentProvider.phonePe);
        expect(event.merchant.value, 'Swiggy');
        expect(
          event.merchant.value,
          isNot('PhonePe'),
          reason: 'the provider must never be confused with the merchant',
        );
      },
    );
  });

  group('CreditCardSemantics end-to-end', () {
    test(
      'a purchase resolves to FinancialEventType.creditCardPurchase deterministically (no AI)',
      () async {
        final provider = _CountingAiProvider();
        final extractor = FinancialEventExtractor(
          aiProvider: provider,
          categoryResolver: categoryResolver,
        );
        final item = await buildItem(
          'Your credit card ending 4821 was charged Rs.2,500 at a merchant.',
        );
        expect(item.parsed, isNotNull);

        final event = await extractor.extract(
          item: item,
          accountMatch: resolvedAccount,
          categories: categories,
        );

        expect(event.eventType, FinancialEventType.creditCardPurchase);
      },
    );
  });
}
