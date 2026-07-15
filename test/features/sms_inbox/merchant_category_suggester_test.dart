import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_memory.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Category category(String id, String name, [CategoryType type = CategoryType.expense]) => Category(
        id: id,
        name: name,
        type: type,
        iconKey: 'shopping',
        colorValue: 0xFF000000,
        createdAt: DateTime(2026),
      );

  final food = category('cat-food', 'Food & Dining');
  final shopping = category('cat-shopping', 'Shopping');
  final salary = category('cat-salary', 'Salary', CategoryType.income);
  final expenseCategories = [food, shopping];

  MerchantMemory memory(
    String key,
    String categoryId, {
    int timesUsed = 1,
    TransactionType type = TransactionType.expense,
    DateTime? lastUsedAt,
  }) =>
      MerchantMemory(
        merchantKey: key,
        transactionType: type,
        categoryId: categoryId,
        timesUsed: timesUsed,
        lastUsedAt: lastUsedAt ?? DateTime(2026, 7, 1),
      );

  group('user history', () {
    test('a remembered choice wins over the seed catalog', () {
      // Swiggy seeds to Food, but this user files it under Shopping. Their
      // own decision is evidence about them; the seed is a generalization.
      final suggester = MerchantCategorySuggester([memory('swiggy', shopping.id)]);

      final result = suggester.suggest(
        merchant: 'SWIGGY',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      expect(result?.categoryId, shopping.id);
      expect(result?.source, SuggestionSource.userHistory);
    });

    test('recalls across the sender formatting variants of one merchant', () {
      final suggester = MerchantCategorySuggester([memory('swiggy order', shopping.id)]);

      final result = suggester.suggest(
        merchant: 'UPI-SWIGGY*ORDER',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      expect(result?.categoryId, shopping.id);
    });

    test('the most-used category wins over a one-off', () {
      final suggester = MerchantCategorySuggester([
        memory('amazon', shopping.id, timesUsed: 5),
        memory('amazon', food.id, timesUsed: 1),
      ]);

      final result = suggester.suggest(
        merchant: 'Amazon',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      expect(result?.categoryId, shopping.id, reason: 'one stray mis-tap must not overturn a long history');
    });

    test('the most recent choice breaks a tie, so a changed mind converges', () {
      final suggester = MerchantCategorySuggester([
        memory('amazon', shopping.id, timesUsed: 3, lastUsedAt: DateTime(2026, 1, 1)),
        memory('amazon', food.id, timesUsed: 3, lastUsedAt: DateTime(2026, 7, 1)),
      ]);

      final result = suggester.suggest(
        merchant: 'Amazon',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      expect(result?.categoryId, food.id);
    });

    test('a memory for the other transaction type is not recalled', () {
      // An Amazon refund (income) must not drag in the Amazon purchase
      // (expense) category.
      final suggester = MerchantCategorySuggester([
        memory('amazon', shopping.id, type: TransactionType.expense),
      ]);

      final result = suggester.suggest(
        merchant: 'Amazon',
        transactionType: TransactionType.income,
        categories: [salary],
      );

      expect(result, isNull);
    });

    test('a memory pointing at a deleted category is ignored, not suggested', () {
      final suggester = MerchantCategorySuggester([memory('swiggy', 'cat-deleted')]);

      final result = suggester.suggest(
        merchant: 'Swiggy',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      // Falls through to the seed rather than suggesting a stale id.
      expect(result?.categoryId, food.id);
      expect(result?.source, SuggestionSource.knownMerchant);
    });
  });

  group('seed catalog', () {
    test('a first-time user still gets Swiggy to Food & Dining', () {
      final result = const MerchantCategorySuggester([]).suggest(
        merchant: 'SWIGGY',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      expect(result?.categoryId, food.id);
      expect(result?.source, SuggestionSource.knownMerchant);
    });

    test('resolves only against categories the user actually has', () {
      // This user deleted Food & Dining. Suggesting it anyway — or inventing
      // it — would be worse than suggesting nothing.
      final result = const MerchantCategorySuggester([]).suggest(
        merchant: 'SWIGGY',
        transactionType: TransactionType.expense,
        categories: [shopping],
      );

      expect(result, isNull);
    });

    test('an unknown merchant gets no seed suggestion', () {
      final result = const MerchantCategorySuggester([]).suggest(
        merchant: 'SOME LOCAL SHOP',
        transactionType: TransactionType.expense,
        categories: expenseCategories,
      );

      expect(result, isNull);
    });
  });

  group('sms type fallback', () {
    test('a salary credit suggests Salary when the merchant is unknown', () {
      final result = const MerchantCategorySuggester([]).suggest(
        merchant: 'INFOSYS',
        transactionType: TransactionType.income,
        categories: [salary],
        smsCategory: SmsTransactionCategory.salaryCredit,
      );

      expect(result?.categoryId, salary.id);
      expect(result?.source, SuggestionSource.smsType);
    });

    test('suggests nothing rather than guessing when no signal fits', () {
      final result = const MerchantCategorySuggester([]).suggest(
        merchant: null,
        transactionType: TransactionType.expense,
        categories: expenseCategories,
        smsCategory: SmsTransactionCategory.unknown,
      );

      expect(result, isNull, reason: 'an unset picker is the honest outcome, exactly as a manual entry starts');
    });
  });
}
