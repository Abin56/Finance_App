import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Provider-agnostic view of the signed-in user. Feature code depends only
/// on this, never on `firebase_auth`'s `User`, so swapping/adding auth
/// providers later never touches anything outside `features/auth`.
class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
  });

  factory AppUser.fromFirebaseUser(User user) {
    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoURL,
    );
  }

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  @override
  List<Object?> get props => [uid, displayName, email, photoUrl];
}
