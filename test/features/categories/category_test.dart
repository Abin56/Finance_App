import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_icons.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryType.appliesTo', () {
    test('income only applies to income transactions', () {
      expect(CategoryType.income.appliesTo(TransactionType.income), isTrue);
      expect(CategoryType.income.appliesTo(TransactionType.expense), isFalse);
    });

    test('expense only applies to expense transactions', () {
      expect(CategoryType.expense.appliesTo(TransactionType.expense), isTrue);
      expect(CategoryType.expense.appliesTo(TransactionType.income), isFalse);
    });

    test('both applies to either transaction type', () {
      expect(CategoryType.both.appliesTo(TransactionType.income), isTrue);
      expect(CategoryType.both.appliesTo(TransactionType.expense), isTrue);
    });
  });

  group('CategoryIcons.iconFor', () {
    test('resolves a known key', () {
      expect(CategoryIcons.iconFor('restaurant'), CategoryIcons.catalog['restaurant']);
    });

    test('falls back to the default icon for an unknown key', () {
      expect(CategoryIcons.iconFor('not-a-real-key'), CategoryIcons.catalog[CategoryIcons.fallback]);
    });
  });

  group('Category Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('categories').withConverter<Category>(
            fromFirestore: Category.fromFirestore,
            toFirestore: (c, _) => c.toFirestore(),
          );

      final original = Category(
        id: 'ignored',
        name: 'Food',
        type: CategoryType.expense,
        iconKey: 'restaurant',
        colorValue: 0xFFFF5B5B,
        createdAt: DateTime(2026, 1, 1),
        isDefault: true,
        isActive: true,
      );

      await collection.doc('c1').set(original);
      final restored = (await collection.doc('c1').get()).data()!;

      expect(restored.id, 'c1');
      expect(restored.name, 'Food');
      expect(restored.type, CategoryType.expense);
      expect(restored.iconKey, 'restaurant');
      expect(restored.colorValue, 0xFFFF5B5B);
      expect(restored.isDefault, isTrue);
      expect(restored.isActive, isTrue);
    });
  });
}
