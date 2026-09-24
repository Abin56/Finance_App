import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../data/transaction_repository.dart';
import '../../domain/transaction.dart';

/// Goes through [firestoreProvider]/[currentUserIdProvider] (not the
/// `FirebaseAuth.instance`/`FirebaseFirestore.instance` singletons
/// directly), so overriding those two providers in tests is enough to run
/// this repository entirely against fakes — same pattern as
/// `accountRepositoryProvider`.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.transactions)
      .withConverter<Transaction>(
        fromFirestore: Transaction.fromFirestore,
        toFirestore: (transaction, _) => transaction.toFirestore(),
      );
  return TransactionRepository(
    collection,
    ref.watch(accountRepositoryProvider),
  );
});

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  return ref.watch(transactionRepositoryProvider).watchAll();
});

/// [transactionsStreamProvider] with every `excludeFromCalculations`
/// transaction and every transfer leg ([Transaction.isTransfer]) removed —
/// the one list every balance/total/report aggregation must watch instead of
/// the raw stream above. A transfer leg (currently only ever created by the
/// web app — see [Transaction.transferId]'s doc comment) moves money between
/// two of the user's own accounts; it's neither real income nor a real
/// expense, so counting it here would double-count it as both. Mirrors the
/// web app's own `isTransfer` exclusion in its Dashboard/Reports hooks.
/// History/Search/Transaction Detail/Calendar/SMS linking must keep watching
/// the raw stream, since an excluded transaction still needs to appear
/// there.
final calculableTransactionsProvider = Provider<List<Transaction>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  return transactions
      .where((t) => !t.excludeFromCalculations && !t.isTransfer)
      .toList();
});

final transactionsTrashStreamProvider = StreamProvider<List<Transaction>>((
  ref,
) {
  return ref.watch(transactionRepositoryProvider).watchTrash();
});
