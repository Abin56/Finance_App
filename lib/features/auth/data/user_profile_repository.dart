import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_constants.dart';
import '../domain/app_user.dart';

/// Keeps the `users/{uid}` document's profile fields in sync with the
/// signed-in Google account.
class UserProfileRepository {
  UserProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Upserts profile fields on every sign-in. `lastLoginAt` is always
  /// bumped; `createdAt` is only written the first time the document is
  /// created, so repeat logins never clobber it.
  Future<void> upsertOnSignIn(AppUser user) async {
    final docRef = _firestore.collection(FirestoreCollections.users).doc(user.uid);
    final snapshot = await docRef.get();

    await docRef.set({
      'uid': user.uid,
      'displayName': user.displayName,
      'email': user.email,
      'photoURL': user.photoUrl,
      'lastLoginAt': FieldValue.serverTimestamp(),
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
