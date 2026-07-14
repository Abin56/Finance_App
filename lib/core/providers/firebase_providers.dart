import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';

/// Single seam every feature repository goes through to reach Firestore/Auth.
/// Overriding these two providers in a `ProviderScope` (e.g. with
/// `fake_cloud_firestore`/`firebase_auth_mocks` in tests) is enough to run
/// the entire app offline against fakes — no feature code needs to know
/// it's under test.
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// The signed-in user's uid, scoping every `users/{uid}/...` Firestore path.
/// Derives from [authStateProvider] (not a direct `FirebaseAuth.instance`
/// read) so it rebuilds reactively on sign-in/out. Throws if watched while
/// signed out or while the initial auth state is still resolving — every
/// screen that reaches a repository provider must only be reachable via a
/// route the router's redirect already gates behind "signed in" (see
/// `app_router.dart`). Screens rendered pre-auth (splash, login) must never
/// watch this provider or any repository provider.
final currentUserIdProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    throw StateError('currentUserIdProvider read before sign-in completed.');
  }
  return user.uid;
});
