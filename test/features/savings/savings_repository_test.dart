import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/savings/data/savings_repository.dart';
import 'package:finance_app/features/savings/domain/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SavingsRepository repository;

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('savingsGoals').withConverter<SavingsGoal>(
          fromFirestore: SavingsGoal.fromFirestore,
          toFirestore: (g, _) => g.toFirestore(),
        );
    repository = SavingsRepository(collection);
  });

  group('SavingsRepository.createGoal', () {
    test('rejects a non-positive target amount', () async {
      await expectLater(
        repository.createGoal(name: 'Bad goal', targetAmount: 0),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('SavingsRepository.contribute', () {
    test('accumulates currentAmount and records an audit entry', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);

      await repository.contribute(goal, 300);

      expect(goal.currentAmount, 300);
      expect(goal.editHistory, hasLength(1));
      expect(goal.editHistory.first.field, 'currentAmount');
    });

    test('rejects a non-positive contribution', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);
      await expectLater(repository.contribute(goal, 0), throwsA(isA<AppException>()));
      await expectLater(repository.contribute(goal, -50), throwsA(isA<AppException>()));
    });

    test('auto-completes the goal once the target is reached', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);

      await repository.contribute(goal, 1000);

      expect(goal.isCompleted, isTrue);
      expect(goal.editHistory.map((e) => e.field), containsAll(['currentAmount', 'isCompleted']));
    });

    test('auto-completes when a contribution overshoots the target', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);

      await repository.contribute(goal, 1500);

      expect(goal.isCompleted, isTrue);
      expect(goal.currentAmount, 1500);
    });

    test('does not re-flip isCompleted on a later contribution past target', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);
      await repository.contribute(goal, 1000);
      final historyLengthAfterFirst = goal.editHistory.length;

      await repository.contribute(goal, 100);

      final completedEntries = goal.editHistory.where((e) => e.field == 'isCompleted');
      expect(completedEntries, hasLength(1));
      expect(goal.editHistory.length, greaterThan(historyLengthAfterFirst));
    });
  });

  group('SavingsRepository.markCompleted / markIncomplete', () {
    test('markCompleted flips isCompleted and is idempotent', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);

      await repository.markCompleted(goal);
      expect(goal.isCompleted, isTrue);

      final historyLength = goal.editHistory.length;
      await repository.markCompleted(goal);
      expect(goal.editHistory.length, historyLength, reason: 'no-op when already completed');
    });

    test('markIncomplete reverses a completed goal', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);
      await repository.markCompleted(goal);

      await repository.markIncomplete(goal);

      expect(goal.isCompleted, isFalse);
    });
  });

  group('SavingsRepository.archive / unarchive', () {
    test('archive hides the goal without soft-deleting it', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);

      await repository.archive(goal);

      expect(goal.isArchived, isTrue);
      expect(goal.isDeleted, isFalse);
    });

    test('unarchive reverses archiving', () async {
      final goal = await repository.createGoal(name: 'Laptop', targetAmount: 1000);
      await repository.archive(goal);

      await repository.unarchive(goal);

      expect(goal.isArchived, isFalse);
    });
  });
}
