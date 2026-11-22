import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/android_update_override.dart';

/// Same collection/doc as `appConfig/androidUpdate` guarded in
/// `firestore.rules` (both repos) — client-readable, admin-write-only, same
/// convention as `smsSyncControl/global`.
const String kAndroidUpdateConfigCollection = 'appConfig';
const String kAndroidUpdateConfigDocId = 'androidUpdate';

/// Streams the operator override doc. Any read failure (offline, denied —
/// e.g. briefly signed out) is swallowed to `null`, matching the update
/// check's fail-open design: an override we can't read is treated the same
/// as no override at all, never as "force mandatory".
class AndroidUpdateOverrideRepository {
  AndroidUpdateOverrideRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<AndroidUpdateOverride?> watch() {
    return _firestore
        .collection(kAndroidUpdateConfigCollection)
        .doc(kAndroidUpdateConfigDocId)
        .snapshots()
        .map((snapshot) => AndroidUpdateOverride.parse(snapshot.data()))
        .handleError((_) {});
  }
}
