import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/category_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_memory.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Category category(String id, String name) => Category(
    id: id,
    name: name,
    type: CategoryType.expense,
    iconKey: 'shopping',
    colorValue: 0xFF000000,
    createdAt: DateTime(2026),
  );

  final food = category('cat-food', 'Food & Dining');
  final categories = [food];

  test(
    'AI category is used when no user-history or seed-catalog match exists',
    () {
      final resolver = CategoryResolver(const MerchantCategorySuggester([]));

      final result = resolver.resolve(
        merchant: 'Some Unknown Merchant',
        transactionType: TransactionType.expense,
        categories: categories,
        aiCategoryName: 'Food & Dining',
      );

      expect(result?.categoryId, 'cat-food');
      expect(result?.source, SuggestionSource.aiInference);
    },
  );

  test('AI category matching is case-insensitive', () {
    final resolver = CategoryResolver(const MerchantCategorySuggester([]));

    final result = resolver.resolve(
      merchant: 'Some Unknown Merchant',
      transactionType: TransactionType.expense,
      categories: categories,
      aiCategoryName: 'food & dining',
    );

    expect(result?.categoryId, 'cat-food');
  });

  test(
    'an AI category name that matches no real category yields no suggestion from that tier',
    () {
      final resolver = CategoryResolver(const MerchantCategorySuggester([]));

      final result = resolver.resolve(
        merchant: 'Some Unknown Merchant',
        transactionType: TransactionType.expense,
        categories: categories,
        aiCategoryName: 'Nonexistent Category',
      );

      expect(
        result,
        isNull,
        reason: 'never invents a category the user does not have',
      );
    },
  );

  test('user history always wins over the AI tier', () {
    final memory = MerchantMemory(
      merchantKey: 'swiggy',
      transactionType: TransactionType.expense,
      categoryId: 'cat-food',
      timesUsed: 3,
      lastUsedAt: DateTime(2026, 7, 1),
    );
    final resolver = CategoryResolver(MerchantCategorySuggester([memory]));

    final result = resolver.resolve(
      merchant: 'Swiggy',
      transactionType: TransactionType.expense,
      categories: categories,
      aiCategoryName: 'Nonexistent Category',
    );

    expect(result?.categoryId, 'cat-food');
    expect(result?.source, SuggestionSource.userHistory);
  });

  test(
    'falls through to the smsType tier when neither history nor AI resolve',
    () {
      final resolver = CategoryResolver(const MerchantCategorySuggester([]));

      final result = resolver.resolve(
        merchant: null,
        transactionType: TransactionType.income,
        categories: [category('cat-salary', 'Salary')],
        smsCategory: SmsTransactionCategory.salaryCredit,
      );

      expect(result?.categoryId, 'cat-salary');
      expect(result?.source, SuggestionSource.smsType);
    },
  );
}
