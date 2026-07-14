import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/budget/domain/budget.dart';
import 'package:finance_app/features/budget/domain/budget_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BudgetType.label', () {
    test('has a distinct label per type', () {
      expect(BudgetType.daily.label, 'Daily');
      expect(BudgetType.monthly.label, 'Monthly');
    });
  });

  group('Budget Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves an overall budget (no category)', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('budgets').withConverter<Budget>(
            fromFirestore: Budget.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final original = Budget(
        id: 'ignored',
        type: BudgetType.daily,
        amount: 500,
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('b1').set(original);
      final restored = (await collection.doc('b1').get()).data()!;

      expect(restored.id, 'b1');
      expect(restored.type, BudgetType.daily);
      expect(restored.amount, 500);
      expect(restored.categoryId, isNull);
      expect(restored.isDeleted, isFalse);
    });

    test('toFirestore/fromFirestore preserves a category budget', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('budgets').withConverter<Budget>(
            fromFirestore: Budget.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final original = Budget(
        id: 'ignored',
        type: BudgetType.monthly,
        amount: 10000,
        categoryId: 'cat-food',
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('b2').set(original);
      final restored = (await collection.doc('b2').get()).data()!;

      expect(restored.categoryId, 'cat-food');
      expect(restored.amount, 10000);
    });
  });
}
