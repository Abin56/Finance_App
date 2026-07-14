import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/budget.dart';
import '../domain/budget_type.dart';

/// Budget-specific persistence on top of the generic CRUD/soft-delete
/// repository, plus the "at most one active budget per (type, categoryId)"
/// invariant — Firestore has no unique-constraint mechanism, so this is
/// enforced here against live data before every create.
class BudgetRepository extends FirestoreCrudRepository<Budget> {
  BudgetRepository(super.collection);

  Future<Budget> createBudget({
    required BudgetType type,
    required double amount,
    String? categoryId,
  }) async {
    if (amount <= 0) {
      throw const AppException('Budget amount must be greater than 0');
    }

    final existing = await getAll();
    final duplicate = existing.any((b) => b.type == type && b.categoryId == categoryId);
    if (duplicate) {
      throw AppException(
        categoryId == null
            ? 'A ${type.label.toLowerCase()} budget already exists'
            : 'This category already has a budget',
      );
    }

    final budget = Budget(
      id: IdGenerator.generate(),
      type: type,
      amount: amount,
      categoryId: categoryId,
      createdAt: DateTime.now(),
    );
    await add(budget.id, budget);
    return budget;
  }

  /// Only the amount is editable post-creation — [Budget.type] and
  /// [Budget.categoryId] define *what* the budget is; changing either would
  /// silently repurpose an existing budget rather than replacing it.
  Future<void> editBudget(Budget budget, {required double amount}) async {
    if (amount <= 0) {
      throw const AppException('Budget amount must be greater than 0');
    }
    budget.updateField(
      field: 'amount',
      oldValue: budget.amount,
      newValue: amount,
      apply: (v) => budget.amount = v,
    );
    await update(budget);
  }
}
