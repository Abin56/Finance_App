import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/savings/domain/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavingsGoal.progress', () {
    test('is 0 when nothing saved', () {
      final goal = SavingsGoal(
        id: 'g1',
        name: 'Laptop',
        targetAmount: 1000,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(goal.progress, 0);
    });

    test('is 0.5 at half the target', () {
      final goal = SavingsGoal(
        id: 'g1',
        name: 'Laptop',
        targetAmount: 1000,
        currentAmount: 500,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(goal.progress, 0.5);
    });

    test('clamps to 1.0 when saved exceeds target', () {
      final goal = SavingsGoal(
        id: 'g1',
        name: 'Laptop',
        targetAmount: 1000,
        currentAmount: 1500,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(goal.progress, 1.0);
    });

    test('does not throw or return NaN/Infinity when target is 0', () {
      final goal = SavingsGoal(
        id: 'g1',
        name: 'Edge case',
        targetAmount: 0,
        currentAmount: 0,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(goal.progress, 0);
      expect(goal.progress.isNaN, isFalse);
    });
  });

  group('SavingsGoal Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('savingsGoals').withConverter<SavingsGoal>(
            fromFirestore: SavingsGoal.fromFirestore,
            toFirestore: (g, _) => g.toFirestore(),
          );

      final original = SavingsGoal(
        id: 'ignored',
        name: 'Emergency fund',
        targetAmount: 50000,
        currentAmount: 12000,
        dueDate: DateTime(2026, 12, 31),
        notes: 'Six months of expenses',
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('g1').set(original);
      final restored = (await collection.doc('g1').get()).data()!;

      expect(restored.id, 'g1');
      expect(restored.name, 'Emergency fund');
      expect(restored.targetAmount, 50000);
      expect(restored.currentAmount, 12000);
      expect(restored.dueDate, DateTime(2026, 12, 31));
      expect(restored.notes, 'Six months of expenses');
      expect(restored.isCompleted, isFalse);
      expect(restored.isArchived, isFalse);
    });

    test('preserves a null due date', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('savingsGoals').withConverter<SavingsGoal>(
            fromFirestore: SavingsGoal.fromFirestore,
            toFirestore: (g, _) => g.toFirestore(),
          );

      final original = SavingsGoal(
        id: 'ignored',
        name: 'No due date',
        targetAmount: 1000,
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('g2').set(original);
      final restored = (await collection.doc('g2').get()).data()!;

      expect(restored.dueDate, isNull);
    });
  });
}
