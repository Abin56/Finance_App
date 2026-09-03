import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_memory.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_category_resolver_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_identity_resolver.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const identityResolver = MerchantIdentityResolver();

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

  MerchantCategoryResolution resolveFor({
    required String merchantGuess,
    required String body,
    List<MerchantMemory> memories = const [],
    required List<Category> categories,
    TransactionType type = TransactionType.expense,
  }) {
    final identity = identityResolver.resolve(
      regexMerchantGuess: merchantGuess,
      smsBody: body,
      memories: memories,
      transactionType: type,
    );
    final suggester = MerchantCategorySuggester(memories);
    final resolver = MerchantAwareCategoryResolver(suggester);
    return resolver.resolve(
      merchant: identity,
      smsBody: body,
      transactionType: type,
      categories: categories,
    );
  }

  group('known merchant with ambiguous category', () {
    test('bare Amazon resolves at medium confidence, not high', () {
      final categories = [category('c1', 'Shopping')];
      final result = resolveFor(
        merchantGuess: 'Amazon',
        body: 'Rs.500 paid to Amazon.',
        categories: categories,
      );
      expect(result.suggestion?.categoryId, 'c1');
      expect(result.confidenceLevel, MerchantConfidenceLevel.medium);
    });

    test(
      'Amazon Prime resolves at high confidence (unambiguous subscription)',
      () {
        final categories = [category('c1', 'Entertainment')];
        final result = resolveFor(
          merchantGuess: 'Amazon Prime',
          body: 'Rs.1499 debited for Amazon Prime membership.',
          categories: categories,
        );
        expect(result.suggestion?.categoryId, 'c1');
        expect(result.confidenceLevel, MerchantConfidenceLevel.high);
      },
    );
  });

  group('grocery vs food delivery', () {
    test(
      'Swiggy resolves Food & Dining while Swiggy Instamart resolves Groceries',
      () {
        final categories = [
          category('food', 'Food & Dining'),
          category('grocery', 'Groceries'),
        ];

        final swiggy = resolveFor(
          merchantGuess: 'Swiggy',
          body: 'Rs.450 paid to Swiggy.',
          categories: categories,
        );
        expect(swiggy.suggestion?.categoryId, 'food');

        final instamart = resolveFor(
          merchantGuess: 'Swiggy Instamart',
          body: 'Rs.450 paid to Swiggy Instamart.',
          categories: categories,
        );
        expect(instamart.suggestion?.categoryId, 'grocery');
      },
    );
  });

  group('user history overriding a catalog/known-merchant hint', () {
    test('a prior user choice for Swiggy wins over the catalog default', () {
      final categories = [
        category('food', 'Food & Dining'),
        category('other', 'Other'),
      ];
      final memories = [
        MerchantMemory(
          merchantKey: 'swiggy',
          transactionType: TransactionType.expense,
          categoryId: 'other',
          timesUsed: 5,
          lastUsedAt: DateTime(2026, 7, 1),
        ),
      ];
      final result = resolveFor(
        merchantGuess: 'Swiggy',
        body: 'Rs.450 paid to Swiggy.',
        memories: memories,
        categories: categories,
      );
      expect(
        result.suggestion?.categoryId,
        'other',
        reason: 'the user\'s own history must outrank the catalog',
      );
      expect(result.suggestion?.source, SuggestionSource.userHistory);
      expect(result.confidenceLevel, MerchantConfidenceLevel.high);
    });
  });

  group('fuel merchants via keyword evidence', () {
    test(
      'an unrecognized fuel station name still resolves Fuel via keyword evidence',
      () {
        final categories = [category('fuel', 'Fuel')];
        final result = resolveFor(
          merchantGuess: 'XYZ Filling Station',
          body: 'Rs.2000 paid at XYZ Filling Station for petrol.',
          categories: categories,
        );
        expect(result.suggestion?.categoryId, 'fuel');
        expect(result.confidenceLevel, MerchantConfidenceLevel.medium);
      },
    );
  });

  group('local unknown merchant with no keyword evidence', () {
    test('category stays unknown — never forced', () {
      final categories = [category('other', 'Other')];
      final result = resolveFor(
        merchantGuess: 'XYZ Traders',
        body: 'Rs.500 paid to XYZ Traders.',
        categories: categories,
      );
      expect(result.isUnknown, isTrue);
    });
  });

  group('AI-only category inference', () {
    test(
      'an AI category name is used only when nothing else resolved, at low confidence',
      () {
        final categories = [category('shop', 'Shopping')];
        final identity = identityResolver.resolve(
          regexMerchantGuess: 'XYZ Traders',
          smsBody: 'Rs.500 paid to XYZ Traders.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        final resolver = MerchantAwareCategoryResolver(
          MerchantCategorySuggester(const []),
        );
        final result = resolver.resolve(
          merchant: identity,
          smsBody: 'Rs.500 paid to XYZ Traders.',
          transactionType: TransactionType.expense,
          categories: categories,
          aiCategoryName: 'Shopping',
        );
        expect(result.suggestion?.categoryId, 'shop');
        expect(result.suggestion?.source, SuggestionSource.aiInference);
        expect(result.confidenceLevel, MerchantConfidenceLevel.low);
      },
    );

    test(
      'AI hallucination prevention: a category name the user does not have is never invented',
      () {
        final categories = [category('shop', 'Shopping')];
        final identity = identityResolver.resolve(
          regexMerchantGuess: 'XYZ Traders',
          smsBody: 'Rs.500 paid to XYZ Traders.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        final resolver = MerchantAwareCategoryResolver(
          MerchantCategorySuggester(const []),
        );
        final result = resolver.resolve(
          merchant: identity,
          smsBody: 'Rs.500 paid to XYZ Traders.',
          transactionType: TransactionType.expense,
          categories: categories,
          aiCategoryName: 'Some Category That Does Not Exist',
        );
        expect(result.isUnknown, isTrue);
      },
    );

    test('AI cannot override a known-merchant match already found', () {
      final categories = [category('food', 'Food & Dining')];
      final identity = identityResolver.resolve(
        regexMerchantGuess: 'Swiggy',
        smsBody: 'Rs.450 paid to Swiggy.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      final resolver = MerchantAwareCategoryResolver(
        MerchantCategorySuggester(const []),
      );
      final result = resolver.resolve(
        merchant: identity,
        smsBody: 'Rs.450 paid to Swiggy.',
        transactionType: TransactionType.expense,
        categories: categories,
        aiCategoryName: 'Shopping',
      );
      expect(
        result.suggestion?.categoryId,
        'food',
        reason: 'the known-merchant hint must win over AI',
      );
      expect(result.suggestion?.source, isNot(SuggestionSource.aiInference));
    });
  });

  group('category unknown / merchant unknown', () {
    test(
      'a fully unresolved merchant with no keyword evidence and no AI stays unknown',
      () {
        final categories = [category('other', 'Other')];
        final result = resolveFor(
          merchantGuess: 'merchant123@upi',
          body: 'Rs.500 sent to merchant123@upi.',
          categories: categories,
        );
        expect(result.isUnknown, isTrue);
      },
    );
  });
}
