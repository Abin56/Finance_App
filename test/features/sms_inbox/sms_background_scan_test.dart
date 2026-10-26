import 'dart:io';

import 'package:finance_app/features/sms_inbox/background/sms_auto_sync_policy.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_entry.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_scan.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_candidate_cloud_sync.dart';
import 'package:finance_app/features/sms_inbox/data/notification_capture_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_auto_sync_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_message_source.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_read_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeReader extends SmsReaderAdapter {
  _FakeReader(this.messages, {this.error});

  List<RawSmsMessage> messages;
  final Object? error;

  @override
  Future<List<RawSmsMessage>> readInbox() async {
    if (error != null) throw error!;
    return messages;
  }
}

class _FakeCaptured extends NotificationCaptureAdapter {
  _FakeCaptured(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readCaptured() async => messages;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDao dao;
  late SmsInboxDatabase database;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    dao = SmsInboxDao(database);
  });

  tearDown(() async => database.database.close());

  final bankSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body:
        'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );
  final otpSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: '123456 is your OTP for txn of Rs.500. Do not share OTP with anyone.',
    date: DateTime(2026, 7, 15, 14, 46),
  );
  final promoSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: 'Pre-approved personal loan up to Rs 5,00,000. Apply now!',
    date: DateTime(2026, 7, 15, 14, 47),
  );

  SmsInboxRepository repo(
    List<RawSmsMessage> sms, {
    List<RawSmsMessage> captured = const [],
    Object? readError,
  }) => SmsInboxRepository(
    dao,
    _FakeReader(sms, error: readError),
    notificationReader: _FakeCaptured(captured),
  );

  test('background scan stores a new bank SMS as a pending item', () async {
    final result = await runBackgroundSmsScan(repo([bankSms]));
    expect(result.success, isTrue);
    expect(result.newItems, 1);
    final items = await dao.getAll();
    expect(items.single.status, SmsImportStatus.pending);
    expect(items.single.parsed?.amount, 1250.0);
  });

  test('re-running (retry / concurrent worker) does not duplicate', () async {
    await runBackgroundSmsScan(repo([bankSms]));
    final second = await runBackgroundSmsScan(repo([bankSms]));
    expect(second.newItems, 0);
    expect(await dao.getAll(), hasLength(1));
  });

  test('a later manual scan of the same SMS adds nothing', () async {
    await runBackgroundSmsScan(repo([bankSms]));
    final manual = await repo([bankSms]).scanInbox();
    expect(manual, 0);
    expect(await dao.getAll(), hasLength(1));
  });

  test('OTP and promotional messages are rejected, never stored', () async {
    final result = await runBackgroundSmsScan(repo([otpSms, promoSms]));
    expect(result.success, isTrue);
    expect(result.newItems, 0);
    expect(await dao.getAll(), isEmpty);
  });

  test(
    'RCS notification duplicate of a device SMS is flagged, not new',
    () async {
      final rcs = RawSmsMessage(
        // Same normalized sender as the device SMS. A display-name title such
        // as "HDFC Bank" would NOT fuzzy-match (pre-existing limit, documented
        // in docs/sms-auto-sync.md).
        address: 'VM-HDFCBK',
        body: bankSms.body,
        date: bankSms.date.add(const Duration(seconds: 40)),
        source: SmsMessageSource.notification,
      );
      final result = await runBackgroundSmsScan(
        repo([bankSms], captured: [rcs]),
      );
      expect(result.success, isTrue);
      final items = await dao.getAll();
      expect(items.where((i) => !i.isDuplicate), hasLength(1));
    },
  );

  group('RCS notification content reaches parser and durable storage', () {
    // Shape produced by NotificationCaptureStore.getAll() -> adapter: title
    // is the conversation display name, source is `notification`.
    RawSmsMessage rcs(String body) => RawSmsMessage(
      address: 'HDFC Bank',
      body: body,
      date: DateTime(2026, 10, 20, 11, 5),
      source: SmsMessageSource.notification,
    );

    test(
      'RCS-only debit alert is parsed and stored as a pending item',
      () async {
        final result = await runBackgroundSmsScan(
          repo(
            const [],
            captured: [
              rcs(
                'Rs. 2,450.00 debited from a/c XX5623 on 20-10-26 to VPA '
                'amazon@apl. Ref No 987654321012.',
              ),
            ],
          ),
        );
        expect(result.newItems, 1);
        final item = (await dao.getAll()).single;
        expect(item.rawMessage.source, SmsMessageSource.notification);
        expect(item.status, SmsImportStatus.pending);
        expect(item.parsed?.amount, 2450.0);
        expect(item.parsed?.referenceNumber, '987654321012');
      },
    );

    test('RCS OTP and personal chat are rejected, never stored', () async {
      final result = await runBackgroundSmsScan(
        repo(
          const [],
          captured: [
            rcs('482913 is your OTP for Rs.2,450 debit. Do not share.'),
            rcs('lunch? I paid already, send me back later'),
            // Personal chats that quote an amount: pass SmsFinancialFilter,
            // must still be stopped by NotificationBankEvidence.
            rcs('I paid Rs 500 for lunch, send it back'),
            rcs('Rs 500 received from you, thanks bro'),
            rcs('Hey I sent you Rs.1200 via UPI for the tickets'),
          ],
        ),
      );
      expect(result.newItems, 0);
      expect(await dao.getAll(), isEmpty);
    });

    test('same RCS row re-read on every scan is stored once', () async {
      final captured = [
        rcs(
          'INR 500.00 credited to a/c XX5623 on 20-10-26 via UPI. Ref 111222333444',
        ),
      ];
      await runBackgroundSmsScan(repo(const [], captured: captured));
      final again = await runBackgroundSmsScan(
        repo(const [], captured: captured),
      );
      expect(again.newItems, 0);
      expect(await dao.getAll(), hasLength(1));
    });
  });

  test('revoked SMS permission reports the short "permission" code', () async {
    final result = await runBackgroundSmsScan(
      repo(const [], readError: const SmsPermissionUnavailableException()),
    );
    expect(result.success, isFalse);
    expect(result.error, 'permission');
  });

  test('other failures report a code that never echoes message text', () async {
    final result = await runBackgroundSmsScan(
      repo(const [], readError: StateError(bankSms.body)),
    );
    expect(result.success, isFalse);
    expect(result.error, 'scan_failed');
    expect(result.toMap().toString(), isNot(contains('debited')));
  });

  test(
    'headless entrypoint is declared in the root library and found natively',
    () {
      // Regression: a pragma'd function in a library nothing imports is never
      // compiled in ("Dart_LookupLibrary ... not found" on device). The entry
      // must live in lib/main.dart and the native side must name it without a
      // library URI.
      final main = File('lib/main.dart').readAsStringSync();
      expect(
        RegExp(
          r"@pragma\('vm:entry-point'\)\s*\n\s*Future<void> smsBackgroundMain\(\)",
        ).hasMatch(main),
        isTrue,
      );
      expect(main, contains('runSmsBackgroundEntry()'));

      final worker = File(
        'android/app/src/main/kotlin/com/flowfi/app/SmsScanWorker.kt',
      ).readAsStringSync();
      expect(worker, contains('"smsBackgroundMain"'));
      expect(worker, isNot(contains('package:finance_app/')));

      final impl = File(
        'lib/features/sms_inbox/background/sms_background_entry.dart',
      ).readAsStringSync();
      expect(impl, isNot(contains('Future<void> smsBackgroundMain(')));
    },
  );

  test(
    'background cloud upload is runtime-controlled; the build has no hard-coded "on" and a build-time kill (the const) removes the path',
    () {
      expect(kSmsAutoSyncCloudUploadRuntimeControlled, isTrue);
      final policy = File(
        'lib/features/sms_inbox/background/sms_auto_sync_policy.dart',
      ).readAsStringSync();
      expect(policy, isNot(contains('kSmsAutoSyncCloudUploadEnabled = true')));
    },
  );

  test(
    'background sources never reference financial-transaction-creation modules (Phase D requirement: no financial transaction creation)',
    () {
      // UPDATED, Phase D (2026-10-24): `cloud_firestore`/`firebase_core`/
      // `firebase_auth` are no longer banned here — Phase D deliberately
      // wires a tombstone-aware Firestore upload into this directory,
      // gated behind `kSmsAutoSyncCloudUploadEnabled` (still `false`; see
      // the dedicated test below). That is the intended, approved change,
      // not a regression of the invariant this test originally guarded.
      // What must still hold, unconditionally, is that nothing in this
      // directory can ever create a real financial record — see the
      // narrower banned list below.
      final files = Directory(
        'lib/features/sms_inbox/background',
      ).listSync().whereType<File>();
      expect(files, isNotEmpty);
      for (final file in files) {
        final source = file.readAsStringSync();
        for (final banned in ['transaction_repository', 'account_repository']) {
          expect(
            source.contains(banned),
            isFalse,
            reason: '${file.path} must not reference $banned',
          );
        }
      }
    },
  );

  test(
    'the background upload step is only ever reached through sms_background_entry.dart, gated by the build flag AND the runtime switch',
    () {
      final entry = File(
        'lib/features/sms_inbox/background/sms_background_entry.dart',
      ).readAsStringSync();
      expect(entry, contains('kSmsAutoSyncCloudUploadRuntimeControlled'));
      expect(
        RegExp(
          r'kSmsAutoSyncCloudUploadRuntimeControlled\s*\?\s*\(\)\s*=>\s*buildBackgroundCloudSync',
        ).hasMatch(entry),
        isTrue,
        reason:
            'cloudSyncBuilder must be conditioned on the flag, not unconditionally built',
      );
      // The builder must go through the runtime switch before touching the
      // candidate collection.
      final builderStart = entry.indexOf(
        'Future<SmsCandidateCloudSync?> buildBackgroundCloudSync',
      );
      expect(builderStart, greaterThan(-1));
      final builder = entry.substring(builderStart);
      expect(
        builder.indexOf('resolveBackgroundUploadGate'),
        lessThan(builder.indexOf('smsTransactionCandidates')),
        reason:
            'the switch must be consulted before the candidate path is built',
      );
    },
  );

  group('SmsAutoSyncStatus', () {
    test('permission revocation makes an enabled Auto Sync ineffective', () {
      final status = SmsAutoSyncStatus.fromMap({
        'supported': true,
        'enabled': true,
        'receiveSmsGranted': false,
        'readSmsGranted': true,
        'lastError': 'permission',
      });
      expect(status.isEffective, isFalse);
      expect(status.permissionsRevoked, isTrue);
      expect(status.errorLabel, contains('permission'));
    });

    test('maps timestamps and counters, zero timestamp means never', () {
      final status = SmsAutoSyncStatus.fromMap({
        'supported': true,
        'enabled': true,
        'receiveSmsGranted': true,
        'readSmsGranted': true,
        'pendingSignals': 2,
        'lastSuccessAt': 0,
      });
      expect(status.isEffective, isTrue);
      expect(status.pendingSignals, 2);
      expect(status.lastSuccessAt, isNull);
      expect(status.errorLabel, isNull);
    });
  });

  group('Phase D (2026-10-24): headless init + upload wiring', () {
    test(
      'ensureFirebaseInitializedForBackground never throws, even with no usable Firebase config in this test process',
      () async {
        await expectLater(ensureFirebaseInitializedForBackground(), completes);
      },
    );

    test(
      'buildBackgroundCloudSync returns null when no uid is resolvable (the realistic state in this test process, and the production state whenever Auth genuinely has no signed-in user)',
      () async {
        final db = await SmsInboxDatabase.openInMemoryForTest();
        final inboxRepository = SmsInboxRepository(
          SmsInboxDao(db),
          _FakeReader(const []),
        );

        final cloudSync = await buildBackgroundCloudSync(db, inboxRepository);

        expect(cloudSync, isNull);
        await db.database.close();
      },
    );

    test(
      'runBackgroundSmsScan never attempts an upload when cloudSyncBuilder is null (the wiring when the build flag is off)',
      () async {
        final result = await runBackgroundSmsScan(repo([bankSms]));

        expect(result.success, isTrue);
        expect(result.uploaded, 0);
        expect(result.uploadSkippedHandled, 0);
        expect(result.uploadError, isNull);
      },
    );

    test(
      'runBackgroundSmsScan treats a null cloudSyncBuilder() result (no verified uid) as "scan succeeded, upload simply not attempted" — not an error',
      () async {
        final result = await runBackgroundSmsScan(
          repo([bankSms]),
          cloudSyncBuilder: () => null,
        );

        expect(result.success, isTrue);
        expect(result.newItems, 1);
        expect(result.uploaded, 0);
        expect(result.uploadError, isNull);
      },
    );

    test(
      'runBackgroundSmsScan fails closed when the cloudSyncBuilder itself throws (e.g. the switch read blew up): scan succeeds, no upload, no error',
      () async {
        final result = await runBackgroundSmsScan(
          repo([bankSms]),
          cloudSyncBuilder: () => throw StateError('switch read failed'),
        );

        expect(result.success, isTrue);
        expect(result.newItems, 1);
        expect(result.uploaded, 0);
        expect(result.uploadError, isNull);
      },
    );

    test(
      'runBackgroundSmsScan awaits an async builder resolving to null (switch OFF) and never uploads',
      () async {
        final result = await runBackgroundSmsScan(
          repo([bankSms]),
          cloudSyncBuilder: () async => null,
        );

        expect(result.success, isTrue);
        expect(result.uploaded, 0);
        expect(result.uploadError, isNull);
      },
    );

    test(
      'runBackgroundSmsScan reports a failed upload attempt separately from a successful scan — local capture is never retroactively marked failed',
      () async {
        final throwingCloudSync = _ThrowingCloudSyncStub();
        final result = await runBackgroundSmsScan(
          repo([bankSms]),
          cloudSyncBuilder: () => throwingCloudSync,
        );

        expect(result.success, isTrue); // the scan itself succeeded
        expect(result.newItems, 1);
        expect(result.uploaded, 0);
        expect(result.uploadError, 'upload_failed');
      },
    );
  });
}

/// Throws from `sync()` — stands in for a Firestore outage/permission-denied
/// during the upload step, proving it never downgrades an already-successful
/// scan result.
class _ThrowingCloudSyncStub implements SmsCandidateCloudSync {
  @override
  Future<SmsCandidateSyncResult> sync({
    bool continueOnUploadError = false,
    Duration? uploadTimeout,
    void Function(SmsCandidateSyncProgress progress)? onProgress,
  }) {
    throw Exception('simulated Firestore outage during background upload');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
