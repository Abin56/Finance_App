import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/constants/firestore_constants.dart';
import '../../../firebase_options.dart';
import '../../accounts/domain/account.dart';
import '../../credit_cards/domain/credit_card_profile.dart';
import '../data/captured_uid_resolver.dart';
import '../data/pending_candidate_generator.dart';
import '../domain/account_card_matcher.dart';
import '../data/sms_inbox_dao.dart';
import '../data/sms_inbox_database.dart';
import '../data/sms_inbox_repository.dart';
import '../data/sms_reader_adapter.dart';
import '../data/sms_sync_diagnostics_store.dart';
import '../domain/sms_availability.dart';
import '../domain/sms_sync_diagnostics.dart';
import '../pairing/sms_device_presence.dart';
import '../pairing/sms_device_status_reporter.dart';
import '../data/sms_transaction_candidate_repository.dart';
import '../data/transaction_candidate_dao.dart';
import '../domain/sms_transaction_candidate_cloud.dart';
import '../presentation/sms_candidate_cloud_sync.dart';
import 'sms_auto_sync_policy.dart';
import 'sms_background_scan.dart';
import 'sms_background_upload_switch.dart';

/// Implementation of the headless scan run by the native `SmsScanWorker`
/// (WorkManager) in its own FlutterEngine; invoked from `smsBackgroundMain` in
/// `main.dart`, which is the actual entrypoint. Reports the outcome over
/// `finance_app/sms_auto_sync_bg` so the worker can retry or finish.
///
/// PHASE D (2026-10-24): now also initializes Firebase (safely — see
/// [ensureFirebaseInitializedForBackground]) and, only when
/// the runtime switch authorizes this account + device (Phase F3,
/// [SmsBackgroundUploadSwitch]), attempts a tombstone-aware upload after the
/// scan succeeds. The switch is OFF unless an operator has written
/// `users/{uid}/smsSyncConfig/backgroundUpload` — see
/// `docs/sms-auto-sync.md` for the activation procedure and
/// `docs/sms-background-cloud-sync-architecture.md` for the verification
/// gates (headless Auth rehydration on real hardware, live-backend proof of
/// the Dart transaction) that single-device activation is meant to exercise.
Future<void> runSmsBackgroundEntry() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel('finance_app/sms_auto_sync_bg');

  // Phase F4: local, content-free health record — one attempt marker now, one
  // outcome write at the end. Never Firestore; never throws.
  const diagnostics = SmsSyncDiagnosticsStore();
  await diagnostics.update((d) => d.applyAttempt(DateTime.now()));

  await ensureFirebaseInitializedForBackground();

  // Live presence for FlowFi Web: scanning → uploading n/total → done.
  // Counts only; never throws; works whether or not the phone is paired.
  final presence = SmsDevicePresenceReporter();
  final previousSync = await SmsDevicePresenceReporter.readSync();
  final progress = SmsPresenceProgressThrottle(presence);
  await progress.update(
    SmsPresenceSync(
      phase: SmsPresenceSyncPhase.scanning,
      updatedAt: DateTime.now(),
      lastSyncAt: previousSync.lastSyncAt,
    ),
  );

  SmsBackgroundScanResult result;
  SmsUploadGate? gate;
  try {
    final db = await SmsInboxDatabase.init();
    final inboxRepository = SmsInboxRepository(
      SmsInboxDao(db),
      const SmsReaderAdapter(),
    );
    result = await runBackgroundSmsScan(
      inboxRepository,
      cloudSyncBuilder: kSmsAutoSyncCloudUploadRuntimeControlled
          ? () => buildBackgroundCloudSync(
              db,
              inboxRepository,
              onGate: (g) => gate = g,
            )
          : null,
      onUploadProgress: (p) => unawaited(
        progress.update(
          SmsPresenceSync(
            phase: SmsPresenceSyncPhase.uploading,
            total: p.total,
            done: p.done,
            uploaded: p.uploaded,
            skipped: p.skipped,
            failed: p.failed,
            updatedAt: DateTime.now(),
            lastSyncAt: previousSync.lastSyncAt,
          ),
        ),
      ),
    );
  } catch (_) {
    result = const SmsBackgroundScanResult.failure('scan_failed');
  }
  await diagnostics.update(
    (d) => applyBackgroundRunDiagnostics(
      d,
      now: DateTime.now(),
      result: result,
      gate: gate,
      cloudControlled: kSmsAutoSyncCloudUploadRuntimeControlled,
    ),
  );
  await progress.flush();
  final last = progress.last;
  final finishedAt = DateTime.now();
  final finished = result.success && result.uploadError == null;
  await presence.report(
    permission: result.error == 'permission' ? SmsAvailability.denied : null,
    autoSyncEnabled: true,
    sync: SmsPresenceSync(
      phase: finished ? SmsPresenceSyncPhase.done : SmsPresenceSyncPhase.failed,
      total: last.total,
      done: last.done,
      uploaded: last.uploaded,
      skipped: last.skipped,
      failed: last.failed,
      updatedAt: finishedAt,
      lastSyncAt: finished ? finishedAt : previousSync.lastSyncAt,
    ),
    force: true,
  );
  // SMS Sync pairing: a paired phone tells FlowFi Web how this run went
  // (no-op otherwise; never throws). The native worker only starts this
  // entry while Auto Sync is on, so that much is known here.
  await SmsDeviceStatusReporter().report(
    permission: result.error == 'permission'
        ? SmsAvailability.denied
        : result.success
        ? SmsAvailability.granted
        : null,
    autoSyncEnabled: true,
    uploadedCount: result.success && gate?.uid != null ? result.uploaded : null,
  );
  await channel.invokeMethod<void>('done', result.toMap());
}

/// Folds one finished background run (and the gate decision it made, if any)
/// into the diagnostics record. Pure — see [SmsSyncDiagnostics.applyRun].
@visibleForTesting
SmsSyncDiagnostics applyBackgroundRunDiagnostics(
  SmsSyncDiagnostics previous, {
  required DateTime now,
  required SmsBackgroundScanResult result,
  required SmsUploadGate? gate,
  required bool cloudControlled,
}) {
  // The sync step only runs when the gate authorized a uid and the scan passed.
  final uploadRan = result.success && gate?.uid != null;
  return previous.applyRun(
    now: now,
    scanSucceeded: result.success,
    scanError: result.error,
    cloudControlled: cloudControlled,
    gateState: gate?.state,
    gateFailure: gate?.failure,
    uploadRan: uploadRan,
    uploaded: result.uploaded,
    skippedNotOwned: result.uploadSkippedNotOwned,
    uploadFailure: result.uploadError == null
        ? null
        : (result.uploadFailure ?? SmsSyncFailureCategory.unknown),
  );
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

/// What the runtime switch said this run, kept apart from the uid it
/// authorizes. [uid] is non-null ONLY when [state] is
/// [SmsCloudSyncState.enabled] — everything else, including "couldn't read it",
/// means no upload (fail closed).
class SmsUploadGate {
  const SmsUploadGate({this.uid, required this.state, this.failure});

  final String? uid;
  final SmsCloudSyncState state;

  /// Privacy-safe reason, set only when [state] is unverified.
  final SmsSyncFailureCategory? failure;
}

/// Resolves [SmsUploadGate] for this run. Two independent conditions, both
/// required (Phase F3): a verified signed-in uid resolves in THIS isolate, AND
/// the runtime switch (`users/{uid}/smsSyncConfig/backgroundUpload`) authorizes
/// this account on this device. Any failure is "no upload", never an error and
/// never a fallback to enabled. Never throws.
@visibleForTesting
Future<SmsUploadGate> resolveBackgroundUploadGate({
  CapturedUidResolver uidResolver = defaultCapturedUidResolver,
  SmsBackgroundUploadSwitch? uploadSwitch,
}) async {
  try {
    final uid = uidResolver();
    if (uid == null) {
      return const SmsUploadGate(
        state: SmsCloudSyncState.unverified,
        failure: SmsSyncFailureCategory.authUnavailable,
      );
    }
    final decision = await (uploadSwitch ?? SmsBackgroundUploadSwitch()).check(
      uid,
    );
    return SmsUploadGate(
      uid: decision.state == SmsCloudSyncState.enabled ? uid : null,
      state: decision.state,
      failure: decision.failure,
    );
  } catch (_) {
    return const SmsUploadGate(
      state: SmsCloudSyncState.unverified,
      failure: SmsSyncFailureCategory.unknown,
    );
  }
}

/// The uid this run may upload for, or `null` for "do not upload" — see
/// [resolveBackgroundUploadGate].
@visibleForTesting
Future<String?> resolveBackgroundUploadUid({
  CapturedUidResolver uidResolver = defaultCapturedUidResolver,
  SmsBackgroundUploadSwitch? uploadSwitch,
}) async => (await resolveBackgroundUploadGate(
  uidResolver: uidResolver,
  uploadSwitch: uploadSwitch,
)).uid;

/// Builds a [SmsCandidateCloudSync] scoped to whatever uid
/// [resolveBackgroundUploadGate] authorizes RIGHT NOW in this isolate — or
/// `null` if there isn't one, which [runBackgroundSmsScan] treats as "don't
/// even attempt an upload this run" (never an error).
///
/// Does NOT assume foreground authentication state automatically carries
/// over: this re-reads `FirebaseAuth.instance.currentUser` fresh, in this
/// process, after [ensureFirebaseInitializedForBackground] has run — if
/// that didn't actually rehydrate a user (unverified, see above), this
/// returns `null` and capture-only behavior is preserved exactly as before
/// Phase D. Likewise, with no (or a non-matching) runtime switch document it
/// returns `null`: OFF is the default for every account and device.
@visibleForTesting
Future<SmsCandidateCloudSync?> buildBackgroundCloudSync(
  SmsInboxDatabase db,
  SmsInboxRepository inboxRepository, {
  CapturedUidResolver uidResolver = defaultCapturedUidResolver,
  SmsBackgroundUploadSwitch? uploadSwitch,

  /// Receives the gate decision (state + privacy-safe reason, no uid use
  /// intended) so the caller can record health diagnostics.
  void Function(SmsUploadGate gate)? onGate,
}) async {
  final gate = await resolveBackgroundUploadGate(
    uidResolver: uidResolver,
    uploadSwitch: uploadSwitch,
  );
  onGate?.call(gate);
  final uid = gate.uid;
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

  // `sync()` uploads local candidate rows, which only the SMS Inbox screen
  // used to build — so a background run captured the SMS but uploaded
  // nothing until the user opened that screen. Build them here too, only
  // once the gate has authorized this uid. A failure skips building (the
  // SMS stays pending for a later run or the screen) but never blocks the
  // upload of candidates that already exist.
  try {
    final built = await generateMissingTransactionCandidates(
      inboxRepository: inboxRepository,
      dao: TransactionCandidateDao(db),
      matcher: () => loadBackgroundAccountCardMatcher(firestore, uid),
    );
    debugPrint('SmsBackground: candidates_built=$built');
  } catch (_) {
    debugPrint('SmsBackground: candidate_build_failed');
  }

  return SmsCandidateCloudSync(
    SmsTransactionCandidateRepository(candidateCollection),
    TransactionCandidateDao(db),
    inboxRepository,
    tombstoneCollection: tombstoneCollection,
  );
}

/// The same account/card data the SMS Inbox screen matches against
/// (`accountsStreamProvider` + `activeCreditCardsProvider`), read once for
/// [uid] since this isolate has no providers. Plain read-only queries (same
/// `deletedAt == null` filter as `FirestoreCrudRepository.getAll`) rather
/// than the repositories, so nothing here can write a financial record.
/// Throws on timeout or a failed read, so the caller builds nothing rather
/// than unmatched candidates.
@visibleForTesting
Future<AccountCardMatcher> loadBackgroundAccountCardMatcher(
  FirebaseFirestore firestore,
  String uid, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final userDoc = firestore.collection(FirestoreCollections.users).doc(uid);
  final accountsSnapshot = await userDoc
      .collection(FirestoreCollections.accounts)
      .withConverter<Account>(
        fromFirestore: Account.fromFirestore,
        toFirestore: (account, _) => account.toFirestore(),
      )
      .where('deletedAt', isNull: true)
      .get()
      .timeout(timeout);
  final cardsSnapshot = await userDoc
      .collection(FirestoreCollections.creditCards)
      .withConverter<CreditCardProfile>(
        fromFirestore: CreditCardProfile.fromFirestore,
        toFirestore: (card, _) => card.toFirestore(),
      )
      .where('deletedAt', isNull: true)
      .get()
      .timeout(timeout);
  final accounts = [for (final doc in accountsSnapshot.docs) doc.data()];
  final cards = [for (final doc in cardsSnapshot.docs) doc.data()];
  // Mirrors `activeCreditCardsProvider`: a card whose account is trashed is
  // not a match target.
  final accountIds = accounts.map((a) => a.id).toSet();
  return AccountCardMatcher(
    accounts: accounts,
    cards: cards.where((c) => accountIds.contains(c.accountId)),
  );
}
