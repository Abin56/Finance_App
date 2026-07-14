import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/app_user.dart';

/// Thrown when the user dismisses the Google account picker without
/// completing sign-in. Not a real error — callers should swallow it.
class SignInCancelledException implements Exception {}

/// Provider-agnostic auth contract. The rest of the app depends only on
/// this — never on `firebase_auth` or `google_sign_in` directly — so
/// another provider (Apple, email/password, ...) can be added later by
/// adding a method here and an implementation, without touching feature code.
abstract class AuthRepository {
  Stream<AppUser?> get authStateChanges;
  AppUser? get currentUser;
  Future<AppUser> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;
  Future<void>? _googleSignInInit;

  @override
  Stream<AppUser?> get authStateChanges =>
      _auth.authStateChanges().map((user) => user == null ? null : AppUser.fromFirebaseUser(user));

  @override
  AppUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : AppUser.fromFirebaseUser(user);
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    // NOTE: Google Sign-In has no supported Windows implementation and no
    // native OAuth SDK ships for desktop Windows; a custom loopback OAuth
    // flow is out of scope for now, so this platform is explicitly
    // unsupported until such a flow is built.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw UnsupportedError('Google Sign-In is not supported on Windows yet.');
    }

    final UserCredential credential;
    if (kIsWeb) {
      credential = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      credential = await _signInWithGoogleNative();
    }

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'null-user', message: 'Sign-in did not return a user.');
    }
    return AppUser.fromFirebaseUser(user);
  }

  Future<UserCredential> _signInWithGoogleNative() async {
    _googleSignInInit ??= GoogleSignIn.instance.initialize();
    await _googleSignInInit;

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw SignInCancelledException();
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token', message: 'Google did not return an ID token.');
    }

    final authCredential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(authCredential);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
