import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/auth_repository.dart';
import '../../data/user_profile_repository.dart';
import '../../domain/app_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(ref.watch(firebaseAuthProvider));
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository(ref.watch(firestoreProvider));
});

/// The reactive seam for auth state — [currentUserIdProvider] derives from
/// this so every repository provider rebuilds correctly on sign-in/out.
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Runs once per sign-in transition: upserts the `users/{uid}` profile doc
/// and purges each feature's expired trash. Kept alive via
/// `ref.watch(authSideEffectsProvider)` in `FinanceApp.build()` so it fires
/// for the whole app lifetime, not just while some particular screen is
/// mounted.
final authSideEffectsProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppUser?>>(authStateProvider, (previous, next) {
    final user = next.value;
    if (user == null) return;
    if (previous?.value?.uid == user.uid) return;

    ref.read(userProfileRepositoryProvider).upsertOnSignIn(user);
    ref.read(accountRepositoryProvider).purgeExpiredTrash(AppConfig.trashRetention);
    ref.read(categoryRepositoryProvider).purgeExpiredTrash(AppConfig.trashRetention);
    ref.read(transactionRepositoryProvider).purgeExpiredTrash(AppConfig.trashRetention);
    ref.read(billRepositoryProvider).purgeExpiredTrash(AppConfig.trashRetention);
  }, fireImmediately: true);
});
