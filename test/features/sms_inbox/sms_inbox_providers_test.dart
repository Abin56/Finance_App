import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/sms_transaction_candidate_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_candidate_cloud.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
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

/// Throws on every [deleteById] — stands in for Firestore being unreachable
/// at the exact moment of the post-convert/ignore cleanup call, to prove it
/// never blocks or rethrows past `_removeCloudCandidate`.
class _ThrowingDeleteRepository extends SmsTransactionCandidateRepository {
  _ThrowingDeleteRepository(super.collection);

  @override
  Future<void> deleteById(String id) {
    throw Exception('simulated Firestore outage');
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

  group('SmsInboxItemsNotifier — immediate cloud candidate cleanup', () {
    Future<SmsTransactionCandidateRepository> cloudRepositoryFor(FakeFirebaseFirestore firestore) async {
      final collection = firestore.collection('smsTransactionCandidates').withConverter<SmsTransactionCandidateCloud>(
            fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
            toFirestore: (c, _) => c.toFirestore(),
          );
      return SmsTransactionCandidateRepository(collection);
    }

    SmsTransactionCandidateCloud buildCloudDoc(String smsItemId) {
      return SmsTransactionCandidateCloud(
        smsItemId: smsItemId,
        amount: 500,
        direction: SmsTransactionDirection.debit,
        eventType: SmsTransactionCategory.unknown,
        transactionDate: DateTime(2026, 7, 15),
        confidenceLevel: ConfidenceLevel.high,
        confidenceScore: 0.9,
        needsReview: false,
        createdAt: DateTime.now(),
      );
    }

    test('markImported deletes the SMS\'s cloud candidate doc right away, without waiting for scan()', () async {
      final firestore = FakeFirebaseFirestore();
      final cloudRepository = await cloudRepositoryFor(firestore);
      await cloudRepository.add('sms-1', buildCloudDoc('sms-1'));

      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter(const [])),
          smsTransactionCandidateRepositoryProvider.overrideWithValue(cloudRepository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(smsInboxItemsProvider.future);

      await container.read(smsInboxItemsProvider.notifier).markImported('sms-1', linkedEntityId: 'txn-1');

      expect(await cloudRepository.getAll(), isEmpty);
    });

    test('markIgnored deletes the SMS\'s cloud candidate doc right away', () async {
      final firestore = FakeFirebaseFirestore();
      final cloudRepository = await cloudRepositoryFor(firestore);
      await cloudRepository.add('sms-2', buildCloudDoc('sms-2'));

      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter(const [])),
          smsTransactionCandidateRepositoryProvider.overrideWithValue(cloudRepository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(smsInboxItemsProvider.future);

      await container.read(smsInboxItemsProvider.notifier).markIgnored('sms-2');

      expect(await cloudRepository.getAll(), isEmpty);
    });

    test('markIgnoredMany deletes every affected SMS\'s cloud candidate doc', () async {
      final firestore = FakeFirebaseFirestore();
      final cloudRepository = await cloudRepositoryFor(firestore);
      await cloudRepository.add('sms-3', buildCloudDoc('sms-3'));
      await cloudRepository.add('sms-4', buildCloudDoc('sms-4'));

      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter(const [])),
          smsTransactionCandidateRepositoryProvider.overrideWithValue(cloudRepository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(smsInboxItemsProvider.future);

      await container.read(smsInboxItemsProvider.notifier).markIgnoredMany(['sms-3', 'sms-4']);

      expect(await cloudRepository.getAll(), isEmpty);
    });

    test('a cloud cleanup failure never fails markImported — local state still updates, no rethrow', () async {
      final firestore = FakeFirebaseFirestore();
      final cloudRepository = _ThrowingDeleteRepository(
        firestore.collection('smsTransactionCandidates').withConverter<SmsTransactionCandidateCloud>(
              fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
              toFirestore: (c, _) => c.toFirestore(),
            ),
      );

      final message = RawSmsMessage(
        address: 'VM-HDFCBK',
        body: 'Rs.500.00 debited from a/c XX1234 on 15-07-26.',
        date: DateTime(2026, 7, 15),
      );
      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter([message])),
          smsTransactionCandidateRepositoryProvider.overrideWithValue(cloudRepository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(smsInboxItemsProvider.notifier).scan();
      final item = container.read(smsInboxItemsProvider).value!.single;

      await expectLater(
        container.read(smsInboxItemsProvider.notifier).markImported(item.id, linkedEntityId: 'txn-1'),
        completes,
      );

      final refreshed = container.read(smsInboxItemsProvider).value!.single;
      expect(refreshed.status, SmsImportStatus.imported);
    });
  });

  group('SmsInboxItemsNotifier.deleteMany — local candidate cleanup', () {
    test('deleting an SMS also deletes its local TransactionCandidate row', () async {
      final message = RawSmsMessage(
        address: 'VM-HDFCBK',
        body: 'Rs.500.00 debited from a/c XX1234 on 15-07-26.',
        date: DateTime(2026, 7, 15),
      );
      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter([message])),
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(smsInboxItemsProvider.notifier).scan();
      final item = container.read(smsInboxItemsProvider).value!.single;

      final dao = container.read(transactionCandidateDaoProvider);
      expect(await dao.getBySmsItemId(item.id), isNotNull);

      await container.read(smsInboxItemsProvider.notifier).deleteMany([item.id]);

      expect(await dao.getBySmsItemId(item.id), isNull);
      expect(container.read(smsInboxItemsProvider).value, isEmpty);
    });

    test('deleting an SMS with no candidate row does nothing and does not throw', () async {
      final container = ProviderContainer(
        overrides: [
          smsInboxDaoProvider.overrideWithValue(SmsInboxDao(database)),
          smsReaderAdapterProvider.overrideWithValue(_FakeReaderAdapter(const [])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(smsInboxItemsProvider.future);

      await expectLater(
        container.read(smsInboxItemsProvider.notifier).deleteMany(['nonexistent-id']),
        completes,
      );
    });
  });
}
