import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ThrowingReaderAdapter extends SmsReaderAdapter {
  const _ThrowingReaderAdapter();

  @override
  Future<List<RawSmsMessage>> readInbox() => throw Exception('platform channel unavailable');
}

class _FakeReaderAdapter extends SmsReaderAdapter {
  _FakeReaderAdapter(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
  });

  tearDown(() async {
    await database.database.close();
  });

  group('SmsInboxItemsNotifier.scan', () {
    test('a read failure is caught and surfaces as AsyncError, not an unhandled exception', () async {
      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(const _ThrowingReaderAdapter()),
        ],
      );
      addTearDown(container.dispose);

      // Let the initial build (a plain getAll(), unaffected by the reader)
      // resolve before triggering the failing scan.
      await container.read(smsInboxItemsProvider.future);

      final newCount = await container.read(smsInboxItemsProvider.notifier).scan();

      expect(newCount, 0);
      expect(container.read(smsInboxItemsProvider), isA<AsyncError<List<Object?>>>());
    });

    test('a successful scan after a prior failure recovers normally', () async {
      final message = RawSmsMessage(
        address: 'VM-HDFCBK',
        body: 'Rs.500.00 debited from a/c XX1234 on 15-07-26.',
        date: DateTime(2026, 7, 15),
      );
      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter([message])),
        ],
      );
      addTearDown(container.dispose);

      final newCount = await container.read(smsInboxItemsProvider.notifier).scan();

      expect(newCount, 1);
      expect(container.read(smsInboxItemsProvider).value, hasLength(1));
    });
  });
}
