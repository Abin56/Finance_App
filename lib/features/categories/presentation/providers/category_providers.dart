import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../data/category_repository.dart';
import '../../domain/category.dart';
import '../../domain/category_type.dart';

/// Goes through [firestoreProvider]/[currentUserIdProvider] (not the
/// `FirebaseAuth.instance`/`FirebaseFirestore.instance` singletons
/// directly), so overriding those two providers in tests is enough to run
/// this repository entirely against fakes — same pattern as
/// `accountRepositoryProvider`.
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.categories)
      .withConverter<Category>(
        fromFirestore: Category.fromFirestore,
        toFirestore: (category, _) => category.toFirestore(),
      );
  return CategoryRepository(collection);
});

/// Seeds the default category set (once, only if the collection is empty)
/// before forwarding Firestore's live snapshot stream, so first-launch
/// users see the starter categories without any explicit setup step.
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) async* {
  final repository = ref.watch(categoryRepositoryProvider);
  await repository.seedDefaultsIfEmpty();
  yield* repository.watchAll();
});

final categoriesTrashStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchTrash();
});

/// Active categories applicable to [transactionType], for populating the
/// transaction form's category picker.
final categoriesForTypeProvider = Provider.family<List<Category>, TransactionType>((ref, transactionType) {
  final categories = ref.watch(categoriesStreamProvider).value ?? const [];
  return categories
      .where((c) => c.isActive && c.type.appliesTo(transactionType))
      .toList();
});
