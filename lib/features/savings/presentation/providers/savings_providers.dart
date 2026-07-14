import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/savings_repository.dart';
import '../../domain/savings_goal.dart';

final savingsRepositoryProvider = Provider<SavingsRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.savingsGoals)
      .withConverter<SavingsGoal>(
        fromFirestore: SavingsGoal.fromFirestore,
        toFirestore: (goal, _) => goal.toFirestore(),
      );
  return SavingsRepository(collection);
});

final savingsGoalsStreamProvider = StreamProvider<List<SavingsGoal>>((ref) {
  return ref.watch(savingsRepositoryProvider).watchAll();
});

final savingsTrashStreamProvider = StreamProvider<List<SavingsGoal>>((ref) {
  return ref.watch(savingsRepositoryProvider).watchTrash();
});

final activeSavingsGoalsProvider = Provider<List<SavingsGoal>>((ref) {
  final goals = ref.watch(savingsGoalsStreamProvider).value ?? const [];
  return goals.where((g) => !g.isArchived).toList();
});

final archivedSavingsGoalsProvider = Provider<List<SavingsGoal>>((ref) {
  final goals = ref.watch(savingsGoalsStreamProvider).value ?? const [];
  return goals.where((g) => g.isArchived).toList();
});

/// Sum of every active (non-archived, non-deleted) goal's saved amount —
/// the headline number for the dashboard Savings card.
final totalSavedProvider = Provider<double>((ref) {
  final goals = ref.watch(activeSavingsGoalsProvider);
  return goals.fold(0.0, (total, g) => total + g.currentAmount);
});
