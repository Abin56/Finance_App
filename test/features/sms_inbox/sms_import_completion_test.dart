import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_prefill.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_import_completion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A repository whose markImported always throws — stands in for a failed
/// linking write (disk error, transient sqflite failure, ...) *after* the
/// caller's own financial record has already been saved.
class _ThrowingMarkImportedRepository extends SmsInboxRepository {
  _ThrowingMarkImportedRepository(super.dao, super.reader);

  @override
  Future<void> markImported(String id, {required String linkedEntityId, String? linkedEntityRoute}) {
    throw Exception('simulated linking failure');
  }
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

  tearDown(() async => database.database.close());

  testWidgets(
    'completeSmsImport swallows a markImported failure instead of throwing '
    '(the caller has already saved its own record by the time this runs)',
    (tester) async {
      final prefill = SmsPrefill(smsId: 'sms-1', amount: 100, dateTime: DateTime(2026, 7, 15));
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
            smsReaderAdapterProvider.overrideWithValue(const SmsReaderAdapter()),
            smsInboxRepositoryProvider.overrideWithValue(
              _ThrowingMarkImportedRepository(SmsInboxDao(database), const SmsReaderAdapter()),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // Must not throw — a failed link is logged, not rethrown.
      await expectLater(
        completeSmsImport(capturedRef, smsPrefill: prefill, linkedEntityId: 'txn-1'),
        completes,
      );
    },
  );

  testWidgets('completeSmsImport is a no-op when smsPrefill is null', (tester) async {
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(const SmsReaderAdapter()),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await expectLater(
      completeSmsImport(capturedRef, smsPrefill: null, linkedEntityId: 'txn-1'),
      completes,
    );
  });
}
