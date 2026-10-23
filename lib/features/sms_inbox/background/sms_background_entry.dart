import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/constants/firestore_constants.dart';
import '../../../firebase_options.dart';
import '../data/captured_uid_resolver.dart';
import '../data/sms_inbox_dao.dart';
import '../data/sms_inbox_database.dart';
import '../data/sms_inbox_repository.dart';
import '../data/sms_reader_adapter.dart';
import '../data/sms_transaction_candidate_repository.dart';
import '../data/transaction_candidate_dao.dart';
import '../domain/sms_transaction_candidate_cloud.dart';
import '../presentation/sms_candidate_cloud_sync.dart';
import 'sms_auto_sync_policy.dart';
import 'sms_background_scan.dart';

/// Implementation of the headless scan run by the native `SmsScanWorker`
/// (WorkManager) in its own FlutterEngine; invoked from `smsBackgroundMain` in
/// `main.dart`, which is the actual entrypoint. Reports the outcome over
/// `finance_app/sms_auto_sync_bg` so the worker can retry or finish.
///
/// PHASE D (2026-10-24): now also initializes Firebase (safely — see
/// [ensureFirebaseInitializedForBackground]) and, only when
/// [kSmsAutoSyncCloudUploadEnabled] is `true`, attempts a tombstone-aware
/// upload after the scan succeeds. The flag stays `false` in production
/// today — see `docs/sms-background-cloud-sync-architecture.md` for exactly
/// which verification gates must pass before it can flip, and the Phase D
/// report for which of those remain unverified (headless Auth rehydration
/// on real hardware, and a live-emulator proof of the Dart transaction —
/// neither achievable on this dev machine, no device/emulator-reachable
/// Dart test harness available).
Future<void> runSmsBackgroundEntry() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel('finance_app/sms_auto_sync_bg');

  await ensureFirebaseInitializedForBackground();

  SmsBackgroundScanResult result;
  try {
    final db = await SmsInboxDatabase.init();
    final inboxRepository = SmsInboxRepository(
      SmsInboxDao(db),
      const SmsReaderAdapter(),
    );
    result = await runBackgroundSmsScan(
      inboxRepository,
      cloudSyncBuilder: kSmsAutoSyncCloudUploadEnabled
          ? () => buildBackgroundCloudSync(db, inboxRepository)
          : null,
    );
  } catch (_) {
    result = const SmsBackgroundScanResult.failure('scan_failed');
  }
  await channel.invokeMethod<void>('done', result.toMap());
}

/// Initializes Firebase in THIS isolate — the headless `FlutterEngine`
/// `SmsScanWorker` starts has never run `main()`, so nothing has called
/// `Firebase.initializeApp()` here before this (the gap identified back in
/// the original root-cause audit). Every failure mode is swallowed by
/// design: a missing/invalid config, the plugin's platform channel not
/// being ready yet, or simply having already been initialized by an earlier
/// call in the same process. Local SMS capture (`scanInbox`) must never
/// depend on this succeeding — Phase C already established that rule for
/// reading auth state; this extends it to the initialization step itself.
///
/// WHETHER THIS ACTUALLY RESTORES THE PREVIOUSLY SIGNED-IN USER IN A
/// HEADLESS ENGINE IS UNVERIFIED. `firebase_auth`'s persistence is backed by
/// native secure storage (Keychain/Keystore) shared across the app's
/// processes, so `FirebaseAuth.instance.currentUser` SHOULD rehydrate
/// without any explicit sign-in call in this isolate — but this has not
/// been exercised on a real device (no Android SDK/adb on this development
/// machine), and nothing about the Dart/Flutter plugin contract guarantees
/// it for a headless engine specifically. Treated as unverified, not
/// assumed: see [buildBackgroundCloudSync], which requires a real,
/// non-null `currentUser.uid` and otherwise skips upload entirely rather
/// than assuming one is available.
@visibleForTesting
Future<void> ensureFirebaseInitializedForBackground() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // Deliberately swallowed — see this function's doc comment. Upload
    // simply won't be attempted this run; local capture is unaffected.
  }
}

/// Builds a [SmsCandidateCloudSync] scoped to whatever uid
/// [defaultCapturedUidResolver] resolves RIGHT NOW in this isolate — or
/// `null` if there isn't one, which [runBackgroundSmsScan] treats as "don't
/// even attempt an upload this run" (never an error).
///
/// Does NOT assume foreground authentication state automatically carries
/// over: this re-reads `FirebaseAuth.instance.currentUser` fresh, in this
/// process, after [ensureFirebaseInitializedForBackground] has run — if
/// that didn't actually rehydrate a user (unverified, see above), this
/// returns `null` and capture-only behavior is preserved exactly as before
/// Phase D.
@visibleForTesting
SmsCandidateCloudSync? buildBackgroundCloudSync(
  SmsInboxDatabase db,
  SmsInboxRepository inboxRepository,
) {
  final uid = defaultCapturedUidResolver();
  if (uid == null) return null;

  final firestore = FirebaseFirestore.instance;
  final candidateCollection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.smsTransactionCandidates)
      .withConverter<SmsTransactionCandidateCloud>(
        fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
        toFirestore: (candidate, _) => candidate.toFirestore(),
      );
  final tombstoneCollection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.smsCandidateTombstones);

  return SmsCandidateCloudSync(
    SmsTransactionCandidateRepository(candidateCollection),
    TransactionCandidateDao(db),
    inboxRepository,
    tombstoneCollection: tombstoneCollection,
  );
}
