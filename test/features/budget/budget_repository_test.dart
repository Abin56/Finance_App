import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/budget/data/budget_repository.dart';
import 'package:finance_app/features/budget/domain/budget.dart';
import 'package:finance_app/features/budget/domain/budget_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BudgetRepository repository;

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('budgets').withConverter<Budget>(
          fromFirestore: Budget.fromFirestore,
          toFirestore: (b, _) => b.toFirestore(),
        );
    repository = BudgetRepository(collection);
  });

  group('BudgetRepository.createBudget', () {
    test('rejects a non-positive amount', () async {
      await expectLater(
        repository.createBudget(type: BudgetType.daily, amount: 0),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a second active overall daily budget', () async {
      await repository.createBudget(type: BudgetType.daily, amount: 500);

      await expectLater(
        repository.createBudget(type: BudgetType.daily, amount: 700),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a second active budget for the same category', () async {
      await repository.createBudget(type: BudgetType.monthly, amount: 10000, categoryId: 'food');

      await expectLater(
        repository.createBudget(type: BudgetType.monthly, amount: 5000, categoryId: 'food'),
        throwsA(isA<AppException>()),
      );
    });

    test('allows daily and monthly overall budgets to coexist', () async {
      await repository.createBudget(type: BudgetType.daily, amount: 500);
      await repository.createBudget(type: BudgetType.monthly, amount: 15000);

      final all = await repository.getAll();
      expect(all, hasLength(2));
    });

    test('allows different categories to each have their own budget', () async {
      await repository.createBudget(type: BudgetType.monthly, amount: 10000, categoryId: 'food');
      await repository.createBudget(type: BudgetType.monthly, amount: 5000, categoryId: 'travel');

      final all = await repository.getAll();
      expect(all, hasLength(2));
    });

    test('allows re-creating a budget after the original was soft-deleted', () async {
      final first = await repository.createBudget(type: BudgetType.daily, amount: 500);
      await repository.softDelete(first);

      final second = await repository.createBudget(type: BudgetType.daily, amount: 800);
      expect(second.amount, 800);
    });
  });

  group('BudgetRepository.editBudget', () {
    test('rejects a non-positive amount', () async {
      final budget = await repository.createBudget(type: BudgetType.daily, amount: 500);
      await expectLater(repository.editBudget(budget, amount: -10), throwsA(isA<AppException>()));
    });

    test('updates the amount and records an audit entry', () async {
      final budget = await repository.createBudget(type: BudgetType.daily, amount: 500);

      await repository.editBudget(budget, amount: 750);

      expect(budget.amount, 750);
      expect(budget.editHistory, hasLength(1));
      expect(budget.editHistory.first.field, 'amount');
    });
  });
}
