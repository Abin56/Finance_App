import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_memory.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_identity_cache.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_intelligence_ai_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_intelligence_service.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_type.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiProvider implements MerchantIntelligenceAiProvider {
  _FakeAiProvider(this._result);
  final MerchantIntelligenceAiResult? _result;
  int callCount = 0;

  @override
  Future<MerchantIntelligenceAiResult?> infer(
    MerchantIntelligenceAiRequest request,
  ) async {
    callCount++;
    return _result;
  }
}

void main() {
  Category category(
    String id,
    String name, {
    CategoryType type = CategoryType.expense,
  }) => Category(
    id: id,
    name: name,
    type: type,
    iconKey: 'other',
    colorValue: 0xFF000000,
    createdAt: DateTime(2026, 1, 1),
  );

  group('AI is skipped when deterministic evidence already answers', () {
    test('a known catalog merchant never triggers an AI call', () async {
      final ai = _FakeAiProvider(const MerchantIntelligenceAiResult.unknown());
      final service = MerchantIntelligenceService(
        suggester: MerchantCategorySuggester(const []),
        aiProvider: ai,
      );
      final result = await service.resolve(
        regexMerchantGuess: 'Swiggy',
        smsBody: 'Rs.450 paid to Swiggy.',
        memories: const [],
        transactionType: TransactionType.expense,
        categories: [category('food', 'Food & Dining')],
      );
      expect(
        ai.callCount,
        0,
        reason: 'known merchants must never cost an AI call',
      );
      expect(result.merchant.displayName, 'Swiggy');
      expect(result.category?.categoryId, 'food');
    });

    test('a user-confirmed merchant never triggers an AI call', () async {
      final ai = _FakeAiProvider(const MerchantIntelligenceAiResult.unknown());
      final memories = [
        MerchantMemory(
          merchantKey: 'ramesh stores',
          transactionType: TransactionType.expense,
          categoryId: 'grocery',
          timesUsed: 4,
          lastUsedAt: DateTime(2026, 7, 1),
        ),
      ];
      final service = MerchantIntelligenceService(
        suggester: MerchantCategorySuggester(memories),
        aiProvider: ai,
      );
      final result = await service.resolve(
        regexMerchantGuess: 'Ramesh Stores',
        smsBody: 'Rs.300 paid to Ramesh Stores.',
        memories: memories,
        transactionType: TransactionType.expense,
        categories: [category('grocery', 'Groceries')],
      );
      expect(ai.callCount, 0);
      expect(result.merchant.isUserConfirmed, isTrue);
    });
  });

  group('AI is consulted only when both identity and category are unresolved', () {
    test(
      'AI fills in an unknown merchant/category when nothing deterministic answered',
      () async {
        final ai = _FakeAiProvider(
          const MerchantIntelligenceAiResult(
            merchantName: 'Some Local Diner',
            category: 'Food & Dining',
            confidence: 0.8,
            evidence: 'body mentions a meal purchase',
          ),
        );
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(const []),
          aiProvider: ai,
        );
        final result = await service.resolve(
          regexMerchantGuess: 'XYZ Traders',
          smsBody: 'Rs.500 paid to XYZ Traders.',
          memories: const [],
          transactionType: TransactionType.expense,
          categories: [category('food', 'Food & Dining')],
        );
        expect(ai.callCount, 1);
        expect(result.merchant.displayName, 'Some Local Diner');
        expect(result.category?.categoryId, 'food');
        expect(result.categoryConfidence, MerchantConfidenceLevel.low);
      },
    );

    test(
      'AI hallucination is capped at low confidence even when the model reports high confidence',
      () async {
        final ai = _FakeAiProvider(
          const MerchantIntelligenceAiResult(
            merchantName: 'Guessed Name',
            category: 'Food & Dining',
            confidence: 0.99,
          ),
        );
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(const []),
          aiProvider: ai,
        );
        final result = await service.resolve(
          regexMerchantGuess: 'XYZ Traders',
          smsBody: 'Rs.500 paid to XYZ Traders.',
          memories: const [],
          transactionType: TransactionType.expense,
          categories: [category('food', 'Food & Dining')],
        );
        expect(
          result.categoryConfidence,
          MerchantConfidenceLevel.low,
          reason:
              'AI-only evidence is always graded low regardless of the model\'s own reported confidence',
        );
      },
    );

    test('AI is never asked to name a person from a phone-number VPA', () async {
      final ai = _FakeAiProvider(const MerchantIntelligenceAiResult.unknown());
      final service = MerchantIntelligenceService(
        suggester: MerchantCategorySuggester(const []),
        aiProvider: ai,
      );
      final result = await service.resolve(
        regexMerchantGuess: '9876543210@oksbi',
        smsBody: 'Rs.450 transferred to 9876543210@oksbi',
        memories: const [],
        transactionType: TransactionType.expense,
        categories: [category('other', 'Other')],
      );
      expect(
        ai.callCount,
        0,
        reason:
            'a bare phone-number VPA must never be handed to AI for identity guessing',
      );
      expect(result.merchant.displayName, isNull);
      expect(result.merchant.merchantType, MerchantType.unknown);
    });
  });

  group('AI cannot override strong evidence even if consulted', () {
    test(
      'user history for Swiggy wins even when an AI opinion is configured',
      () async {
        final memories = [
          MerchantMemory(
            merchantKey: 'swiggy',
            transactionType: TransactionType.expense,
            categoryId: 'other',
            timesUsed: 5,
            lastUsedAt: DateTime(2026, 7, 1),
          ),
        ];
        final ai = _FakeAiProvider(
          const MerchantIntelligenceAiResult(
            merchantName: 'Swiggy',
            category: 'Shopping',
            confidence: 0.9,
          ),
        );
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(memories),
          aiProvider: ai,
        );
        final result = await service.resolve(
          regexMerchantGuess: 'Swiggy',
          smsBody: 'Rs.450 paid to Swiggy.',
          memories: memories,
          transactionType: TransactionType.expense,
          categories: [
            category('food', 'Food & Dining'),
            category('other', 'Other'),
          ],
        );
        expect(
          ai.callCount,
          0,
          reason:
              'user history already answers everything, so AI is never even called',
        );
        expect(result.category?.categoryId, 'other');
      },
    );
  });

  group('cache', () {
    test(
      'a cached identity is reused instead of recomputing on the next call',
      () async {
        final cache = MerchantIdentityCache();
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(const []),
          cache: cache,
        );
        final categories = [category('food', 'Food & Dining')];

        final first = await service.resolve(
          regexMerchantGuess: 'Swiggy',
          smsBody: 'Rs.450 paid to Swiggy.',
          memories: const [],
          transactionType: TransactionType.expense,
          categories: categories,
        );
        expect(cache.length, 1);

        final second = await service.resolve(
          regexMerchantGuess: 'Swiggy',
          smsBody: 'Rs.450 paid to Swiggy.',
          memories: const [],
          transactionType: TransactionType.expense,
          categories: categories,
        );
        expect(second.merchant.displayName, first.merchant.displayName);
      },
    );

    test(
      'invalidating a cached key forces fresh resolution afterward',
      () async {
        final cache = MerchantIdentityCache();
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(const []),
          cache: cache,
        );
        await service.resolve(
          regexMerchantGuess: 'Swiggy',
          smsBody: 'Rs.450 paid to Swiggy.',
          memories: const [],
          transactionType: TransactionType.expense,
          categories: [category('food', 'Food & Dining')],
        );
        expect(cache.get('swiggy'), isNotNull);
        cache.invalidate('swiggy');
        expect(cache.get('swiggy'), isNull);
      },
    );
  });

  group('adversarial: amount/keyword traps', () {
    test(
      'a promo-shaped merchant guess with no real evidence stays unknown, never forced to Food',
      () async {
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(const []),
        );
        final result = await service.resolve(
          regexMerchantGuess: 'XYZ Traders',
          smsBody: 'Rs.50 paid to XYZ Traders.',
          memories: const [],
          transactionType: TransactionType.expense,
          categories: [category('food', 'Food & Dining')],
        );
        expect(
          result.category,
          isNull,
          reason:
              'a small amount alone must never bias category resolution toward Food',
        );
      },
    );

    test(
      'a credit "received from Swiggy" is not forced into a Food & Dining expense',
      () async {
        final service = MerchantIntelligenceService(
          suggester: MerchantCategorySuggester(const []),
        );
        final result = await service.resolve(
          regexMerchantGuess: 'Swiggy',
          smsBody: 'Rs.500 received from Swiggy as a refund.',
          memories: const [],
          transactionType: TransactionType.income,
          categories: [
            category('food', 'Food & Dining'),
            category('refund', 'Other', type: CategoryType.both),
          ],
        );
        // Merchant identity itself is still correctly Swiggy...
        expect(result.merchant.displayName, 'Swiggy');
        // ...but resolved against the income side, not silently defaulted to
        // the expense-side Food & Dining category.
        expect(result.category?.categoryId, isNot('food'));
      },
    );
  });
}
