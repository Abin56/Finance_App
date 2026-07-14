import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/savings_goal.dart';

/// Savings-goal-specific persistence on top of the generic CRUD/soft-delete
/// repository.
class SavingsRepository extends FirestoreCrudRepository<SavingsGoal> {
  SavingsRepository(super.collection);

  Future<SavingsGoal> createGoal({
    required String name,
    required double targetAmount,
    DateTime? dueDate,
    String notes = '',
  }) async {
    if (targetAmount <= 0) {
      throw const AppException('Target amount must be greater than 0');
    }
    final goal = SavingsGoal(
      id: IdGenerator.generate(),
      name: name,
      targetAmount: targetAmount,
      dueDate: dueDate,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await add(goal.id, goal);
    return goal;
  }

  Future<void> editGoal(
    SavingsGoal goal, {
    String? name,
    double? targetAmount,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? notes,
  }) async {
    if (targetAmount != null && targetAmount <= 0) {
      throw const AppException('Target amount must be greater than 0');
    }
    goal.updateField(field: 'name', oldValue: goal.name, newValue: name, apply: (v) => goal.name = v);
    goal.updateField(
      field: 'targetAmount',
      oldValue: goal.targetAmount,
      newValue: targetAmount,
      apply: (v) => goal.targetAmount = v,
    );
    if (clearDueDate && goal.dueDate != null) {
      goal.recordEdit(field: 'dueDate', oldValue: goal.dueDate.toString(), newValue: 'none');
      goal.dueDate = null;
    } else {
      goal.updateField(
        field: 'dueDate',
        oldValue: goal.dueDate,
        newValue: dueDate,
        apply: (v) => goal.dueDate = v,
      );
    }
    goal.updateField(field: 'notes', oldValue: goal.notes, newValue: notes, apply: (v) => goal.notes = v);
    await update(goal);
  }

  /// Adds [amount] toward the goal, audit-tracked. Auto-completes the goal
  /// once the contribution brings it to or past its target — recorded as
  /// its own audit entry alongside the contribution, so both are visible
  /// in [SavingsGoal.editHistory].
  Future<void> contribute(SavingsGoal goal, double amount) async {
    if (amount <= 0) {
      throw const AppException('Amount must be greater than 0');
    }
    final newAmount = goal.currentAmount + amount;
    goal.recordEdit(
      field: 'currentAmount',
      oldValue: goal.currentAmount.toString(),
      newValue: newAmount.toString(),
    );
    goal.currentAmount = newAmount;

    if (!goal.isCompleted && newAmount >= goal.targetAmount) {
      goal.recordEdit(field: 'isCompleted', oldValue: 'false', newValue: 'true');
      goal.isCompleted = true;
    }

    await update(goal);
  }

  Future<void> markCompleted(SavingsGoal goal) async {
    if (goal.isCompleted) return;
    goal.recordEdit(field: 'isCompleted', oldValue: 'false', newValue: 'true');
    goal.isCompleted = true;
    await update(goal);
  }

  Future<void> markIncomplete(SavingsGoal goal) async {
    if (!goal.isCompleted) return;
    goal.recordEdit(field: 'isCompleted', oldValue: 'true', newValue: 'false');
    goal.isCompleted = false;
    await update(goal);
  }

  /// Hides a goal from the primary active list without soft-deleting it —
  /// archiving is a user-visible organizational action (the "Archive
  /// Completed Goals" requirement), not a delete, so it's kept separate
  /// from the trash/soft-delete mechanism.
  Future<void> archive(SavingsGoal goal) async {
    if (goal.isArchived) return;
    goal.recordEdit(field: 'isArchived', oldValue: 'false', newValue: 'true');
    goal.isArchived = true;
    await update(goal);
  }

  Future<void> unarchive(SavingsGoal goal) async {
    if (!goal.isArchived) return;
    goal.recordEdit(field: 'isArchived', oldValue: 'true', newValue: 'false');
    goal.isArchived = false;
    await update(goal);
  }
}
