import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/account_repository.dart';
import '../../domain/account.dart';

/// The repository is the only Riverpod-managed piece; the account *list*
/// itself is observed via [accountsStreamProvider]/[accountsTrashStreamProvider],
/// which wrap Firestore's own snapshot stream, so the UI always reflects
/// what's cached/synced without a duplicate in-memory state layer to keep
/// in sync.
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.accounts)
      .withConverter<Account>(
        fromFirestore: Account.fromFirestore,
        toFirestore: (account, _) => account.toFirestore(),
      );
  return AccountRepository(collection);
});

final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).watchAll();
});

final accountsTrashStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).watchTrash();
});

final netWorthProvider = Provider<double>((ref) {
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  return accounts.fold(0.0, (total, account) => total + account.currentBalance);
});
