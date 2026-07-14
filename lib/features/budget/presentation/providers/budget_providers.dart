import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/budget_repository.dart';
import '../../domain/budget.dart';
import '../../domain/budget_type.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.budgets)
      .withConverter<Budget>(
        fromFirestore: Budget.fromFirestore,
        toFirestore: (budget, _) => budget.toFirestore(),
      );
  return BudgetRepository(collection);
});

final budgetsStreamProvider = StreamProvider<List<Budget>>((ref) {
  return ref.watch(budgetRepositoryProvider).watchAll();
});

final budgetsTrashStreamProvider = StreamProvider<List<Budget>>((ref) {
  return ref.watch(budgetRepositoryProvider).watchTrash();
});

/// The single active overall daily budget, if one has been set.
final dailyBudgetProvider = Provider<Budget?>((ref) {
  final budgets = ref.watch(budgetsStreamProvider).value ?? const [];
  return budgets.where((b) => b.type == BudgetType.daily && b.categoryId == null).firstOrNull;
});

/// The single active overall monthly budget, if one has been set.
final monthlyBudgetProvider = Provider<Budget?>((ref) {
  final budgets = ref.watch(budgetsStreamProvider).value ?? const [];
  return budgets.where((b) => b.type == BudgetType.monthly && b.categoryId == null).firstOrNull;
});

/// Every active per-category budget (always monthly — see [BudgetType]).
final categoryBudgetsProvider = Provider<List<Budget>>((ref) {
  final budgets = ref.watch(budgetsStreamProvider).value ?? const [];
  return budgets.where((b) => b.type == BudgetType.monthly && b.categoryId != null).toList();
});

/// Total expense spending for today, for the Daily Budget card.
final todaySpentProvider = Provider<double>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  return transactions
      .where((t) => t.type == TransactionType.expense && t.dateTime.isToday)
      .fold(0.0, (total, t) => total + t.amount);
});

/// Total expense spending for [month] (any day within it), for the Monthly
/// Budget card and its month-selector history view.
final monthSpentProvider = Provider.family<double, DateTime>((ref, month) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  return transactions
      .where((t) => t.type == TransactionType.expense && t.dateTime.isSameMonth(month))
      .fold(0.0, (total, t) => total + t.amount);
});

/// This month's expense spending for a single category, for category
/// budget rows.
final categorySpentProvider = Provider.family<double, String>((ref, categoryId) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  final now = DateTime.now();
  return transactions
      .where(
        (t) =>
            t.type == TransactionType.expense &&
            t.categoryId == categoryId &&
            t.dateTime.isSameMonth(now),
      )
      .fold(0.0, (total, t) => total + t.amount);
});
