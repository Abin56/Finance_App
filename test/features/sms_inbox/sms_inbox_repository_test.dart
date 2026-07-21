import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_duplicate_reason.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSmsReaderAdapter extends SmsReaderAdapter {
  _FakeSmsReaderAdapter(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
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

  tearDown(() async {
    await database.database.close();
  });

  final financialSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );

  final otpSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: '123456 is your OTP for txn of Rs.500. Do not share OTP with anyone.',
    date: DateTime(2026, 7, 15, 14, 46),
  );

  group('scanInbox', () {
    test('inserts a new item for a financial SMS', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      final newCount = await repository.scanInbox();

      expect(newCount, 1);
      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.first.status, SmsImportStatus.pending);
      expect(all.first.parsed?.amount, 1250.0);
    });

    test('drops non-financial SMS entirely', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([otpSms]));
      final newCount = await repository.scanInbox();

      expect(newCount, 0);
      expect(await repository.getAll(), isEmpty);
    });

    test('re-scanning the same messages is idempotent (no duplicate rows)', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));

      await repository.scanInbox();
      final secondScanCount = await repository.scanInbox();

      expect(secondScanCount, 0);
      expect(await repository.getAll(), hasLength(1));
    });

    test('stores a re-sent duplicate rather than discarding it, flagged against the original', () async {
      // Same payment, same reference number, re-sent from the bank's other
      // DLT sender id — a different physical SMS describing one event.
      final resent = RawSmsMessage(
        address: 'AX-HDFCBK',
        body: '${financialSms.body} Download our app!',
        date: financialSms.date,
      );
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms, resent]));

      expect(await repository.scanInbox(), 2);

      final all = await repository.getAll();
      expect(all, hasLength(2), reason: 'the duplicate must be kept, not silently dropped');

      final original = all.firstWhere((item) => !item.isDuplicate);
      final duplicate = all.firstWhere((item) => item.isDuplicate);
      expect(duplicate.duplicateOfId, original.id);
      expect(duplicate.duplicateReason, SmsDuplicateReason.sameReferenceNumber);
    });

    test('re-scanning does not re-flag stored messages as duplicates of themselves', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));

      await repository.scanInbox();
      await repository.scanInbox();

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.isDuplicate, isFalse);
    });

    test('a second duplicate points at the original, never at the first duplicate', () async {
      RawSmsMessage variant(String sender, String suffix) => RawSmsMessage(
            address: sender,
            body: '${financialSms.body} $suffix',
            date: financialSms.date,
          );

      final repository = SmsInboxRepository(
        dao,
        _FakeSmsReaderAdapter([financialSms, variant('AX-HDFCBK', 'a'), variant('JD-HDFCBK', 'b')]),
      );
      await repository.scanInbox();

      final all = await repository.getAll();
      final original = all.firstWhere((item) => !item.isDuplicate);
      final duplicates = all.where((item) => item.isDuplicate).toList();

      expect(duplicates, hasLength(2));
      // A flat chain is what lets a duplicate be deleted without orphaning
      // the others behind it.
      expect(duplicates.every((item) => item.duplicateOfId == original.id), isTrue);
    });

    test('a genuinely different payment from the same sender is not a duplicate', () async {
      final otherPayment = RawSmsMessage(
        address: 'VM-HDFCBK',
        body: 'Rs.980.00 debited from a/c XX5623 on 15-07-26 to VPA zomato@icici. Ref No 999888777666.',
        date: DateTime(2026, 7, 15, 18, 5),
      );
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms, otherPayment]));
      await repository.scanInbox();

      final all = await repository.getAll();
      expect(all.where((item) => item.isDuplicate), isEmpty);
    });

    test('clearDuplicateFlag returns a false positive to the normal inbox', () async {
      final resent = RawSmsMessage(
        address: 'AX-HDFCBK',
        body: '${financialSms.body} extra',
        date: financialSms.date,
      );
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms, resent]));
      await repository.scanInbox();

      final duplicate = (await repository.getAll()).firstWhere((item) => item.isDuplicate);
      await repository.clearDuplicateFlag(duplicate.id);

      final updated = (await repository.getAll()).firstWhere((item) => item.id == duplicate.id);
      expect(updated.isDuplicate, isFalse);
      expect(updated.duplicateReason, isNull);
    });

    test('a single scan with several brand-new messages reports the correct batched count', () async {
      // Regression: scanInbox used to insert one row at a time; batching
      // the inserts (via db.batch()) must still report the same accurate
      // new-item count, including on backends that report an ignored
      // conflict as `null` rather than `0`.
      final second = RawSmsMessage(
        address: 'VM-ICICIB',
        body: 'Rs.980.00 debited from a/c XX9999 on 15-07-26 to VPA zomato@icici. Ref No 111222333444.',
        date: DateTime(2026, 7, 15, 19, 0),
      );
      final third = RawSmsMessage(
        address: 'VM-SBIBNK',
        body: 'Rs.2,000.00 credited to a/c XX8888 on 15-07-26. Info: NEFT.',
        date: DateTime(2026, 7, 15, 20, 0),
      );
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms, second, third]));

      expect(await repository.scanInbox(), 3);
      expect(await repository.getAll(), hasLength(3));
    });

    test('a batched scan mixing already-stored and brand-new messages counts only the new ones', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();

      final second = RawSmsMessage(
        address: 'VM-ICICIB',
        body: 'Rs.980.00 debited from a/c XX9999 on 15-07-26 to VPA zomato@icici. Ref No 111222333444.',
        date: DateTime(2026, 7, 15, 19, 0),
      );
      final rescanRepository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms, second]));
      expect(await rescanRepository.scanInbox(), 1, reason: 'only the second message is new');
      expect(await rescanRepository.getAll(), hasLength(2));
    });

    test('a converted item stays imported across a re-scan', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();

      final item = (await repository.getAll()).single;
      await repository.markImported(item.id, linkedEntityId: 'txn-1');

      await repository.scanInbox();

      final reloaded = (await repository.getAll()).single;
      expect(reloaded.status, SmsImportStatus.imported);
      expect(reloaded.linkedEntityId, 'txn-1');
    });
  });

  group('status transitions', () {
    test('markIgnored moves an item to ignored, restore moves it back to pending', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();
      final item = (await repository.getAll()).single;

      await repository.markIgnored(item.id);
      expect((await repository.getAll()).single.status, SmsImportStatus.ignored);

      await repository.restore(item.id);
      expect((await repository.getAll()).single.status, SmsImportStatus.pending);
    });

    test('restore clears the stale ignoredAt timestamp rather than leaving it behind', () async {
      // Regression: updateStatus's conditional map-entry syntax omitted the
      // 'ignored_at' column entirely when no new value was given, so a
      // restored item kept its old ignore timestamp even though it was
      // pending again.
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();
      final item = (await repository.getAll()).single;

      await repository.markIgnored(item.id);
      expect((await repository.getAll()).single.ignoredAt, isNotNull);

      await repository.restore(item.id);
      expect((await repository.getAll()).single.ignoredAt, isNull);
    });

    test('getByStatus filters correctly', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();
      final item = (await repository.getAll()).single;
      await repository.markIgnored(item.id);

      expect(await repository.getByStatus(SmsImportStatus.ignored), hasLength(1));
      expect(await repository.getByStatus(SmsImportStatus.pending), isEmpty);
    });

    test('deleteMany removes items permanently', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();
      final item = (await repository.getAll()).single;

      await repository.deleteMany([item.id]);
      expect(await repository.getAll(), isEmpty);
    });

    test('a deleted item does not reappear on a later re-scan of the same device inbox', () async {
      final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([financialSms]));
      await repository.scanInbox();
      final item = (await repository.getAll()).single;

      await repository.deleteMany([item.id]);
      expect(await repository.getAll(), isEmpty);

      // Same physical message still sits in the device inbox and gets
      // re-read on the next scan/app restart — it must stay gone.
      final newCount = await repository.scanInbox();
      expect(newCount, 0);
      expect(await repository.getAll(), isEmpty);
    });
  });
}
