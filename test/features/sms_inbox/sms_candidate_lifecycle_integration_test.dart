import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/sms_inbox/data/merchant_memory_dao.dart';
import 'package:finance_app/features/sms_inbox/data/merchant_memory_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/sms_transaction_candidate_repository.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_candidate_cloud.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate_builder.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_candidate_cloud_sync.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_import_completion.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';
// sqflite exports its own `Transaction`, which collides with the app's.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// True end-to-end coverage of the Android SMS candidate lifecycle, chaining
/// the *real* collaborators together rather than exercising each in
/// isolation (which `sms_candidate_cloud_sync_test.dart`,
/// `transaction_candidate_builder_test.dart`, and
/// `sms_transaction_candidate_cloud_test.dart` already do):
///
///   raw SMS -> SmsInboxRepository.scanInbox() (real parser registry)
///   -> TransactionCandidateBuilder (real AccountCardMatcher against a real Account)
///   -> SmsCandidateCloudSync.sync() -> users/{uid}/smsTransactionCandidates/{id}
///   -> assert the exact raw, web-readable document shape
///   -> convert (TransactionRepository.createTransaction, source: 'sms')
///   -> linkSmsImportViaRepositories (markImported + immediate cloud cleanup)
///   -> assert the candidate doc is gone and local SMS/candidate state is
///      consistent with the conversion.
///
/// No Firebase emulator is used: this repo has no emulator harness (no
/// `emulators` block in firebase.json, no rules-unit-testing setup), and
/// building one is out of scope for an integration/hardening pass.
/// `fake_cloud_firestore` already gives an in-memory Firestore that proves
/// exactly what a web reader would see in the document (field names, exact
/// string/enum values, absence of raw SMS content) — the one thing it does
/// NOT prove is `firestore.rules` enforcement, which is out of reach without
/// the real emulator and is called out as a residual gap in the final report
/// rather than silently assumed to be covered here.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late SmsInboxRepository inboxRepository;
  late TransactionCandidateDao candidateDao;
  late FakeFirebaseFirestore firestore;
  late SmsTransactionCandidateRepository cloudCandidateRepository;
  late SmsCandidateCloudSync cloudSync;
  late AccountRepository accountRepository;
  late TransactionRepository transactionRepository;
  late MerchantMemoryRepository memoryRepository;
  late String accountId;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    inboxRepository = SmsInboxRepository(
      SmsInboxDao(database),
      const SmsReaderAdapter(),
    );
    candidateDao = TransactionCandidateDao(database);
    memoryRepository = MerchantMemoryRepository(MerchantMemoryDao(database));

    firestore = FakeFirebaseFirestore();

    final accountCollection = firestore
        .collection('accounts')
        .withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    accountRepository = AccountRepository(accountCollection);

    final transactionCollection = firestore
        .collection('transactions')
        .withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    transactionRepository = TransactionRepository(
      transactionCollection,
      accountRepository,
    );

    final candidateCollection = firestore
        .collection('smsTransactionCandidates')
        .withConverter<SmsTransactionCandidateCloud>(
          fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    cloudCandidateRepository = SmsTransactionCandidateRepository(
      candidateCollection,
    );
    cloudSync = SmsCandidateCloudSync(
      cloudCandidateRepository,
      candidateDao,
      inboxRepository,
    );
  });

  tearDown(() async {
    await database.database.close();
  });

  /// Runs the exact sequence `SmsInboxItemsNotifier.scan()` runs, but against
  /// plain repositories instead of a `Ref` — a real bank SMS in, a real
  /// candidate built and persisted locally, out.
  Future<void> scanAndBuildCandidates(
    List<RawSmsMessage> messages,
    AccountCardMatcher matcher,
  ) async {
    final reader = _FakeReaderAdapter(messages);
    inboxRepository = SmsInboxRepository(SmsInboxDao(database), reader);
    cloudSync = SmsCandidateCloudSync(
      cloudCandidateRepository,
      candidateDao,
      inboxRepository,
    );

    await inboxRepository.scanInbox();
    final pending = await inboxRepository.getByStatus(SmsImportStatus.pending);
    final builder = TransactionCandidateBuilder(matcher);
    for (final item in pending) {
      final candidate = builder.build(item);
      if (candidate != null) await candidateDao.upsert(candidate);
    }
  }

  test('full pipeline: real SMS -> parsed -> matched candidate -> cloud doc with the exact '
      'web-readable shape -> conversion -> immediate cloud cleanup', () async {
    final account = await accountRepository.createAccount(
      name: 'HDFC Savings',
      type: AccountType.bank,
      openingBalance: 5000,
      colorValue: 0xFF00FF00,
      bankId: 'hdfc',
      accountNumberLast4: '5623',
    );
    accountId = account.id;

    final matcher = AccountCardMatcher(
      accounts: [account],
      cards: const <CreditCardProfile>[],
    );

    final message = RawSmsMessage(
      address: 'VM-HDFCBK',
      body:
          'Rs.1,250.50 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
      date: DateTime(2026, 7, 15, 14, 45),
    );

    // --- 1. Scan -> parse -> candidate build (real collaborators) ---
    await scanAndBuildCandidates([message], matcher);

    final smsItem = (await inboxRepository.getAll()).single;
    expect(smsItem.status, SmsImportStatus.pending);
    expect(
      smsItem.parsed,
      isNotNull,
      reason: 'the bank-specific HDFC parser must recognize this message',
    );

    final localCandidate = await candidateDao.getBySmsItemId(smsItem.id);
    expect(localCandidate, isNotNull);
    expect(
      localCandidate!.matchedAccountId,
      accountId,
      reason: 'last-4 5623 must resolve to the seeded account',
    );

    // --- 2. Candidate -> Firestore candidate ---
    final syncResult = await cloudSync.sync();
    expect(syncResult.synced, 1);
    expect(syncResult.removed, 0);

    // --- 3. Exact web-readable document shape at the authoritative path ---
    // This test wires the repository to the bare `smsTransactionCandidates`
    // collection directly (as every other test in this suite does); the
    // real app scopes it under `users/{uid}/...` at the provider layer
    // (see `smsTransactionCandidateRepositoryProvider`), which doesn't
    // change the document's own shape — only its parent path.
    final snapshot = await firestore
        .collection('smsTransactionCandidates')
        .doc(smsItem.id)
        .get();
    final raw = snapshot.data()!;

    expect(
      snapshot.id,
      smsItem.id,
      reason:
          'the document id must be the local SmsInboxItem id, not a random id',
    );
    expect(raw['amount'], 1250.5);
    expect(raw['direction'], 'debit');
    expect(raw['eventType'], isA<String>());
    expect(raw['transactionDate'], isNotNull);
    expect(raw['accountId'], accountId);
    expect(raw['cardId'], isNull);
    expect(raw['confidenceLevel'], isA<String>());
    expect(raw['confidenceScore'], isA<num>());
    expect(raw['needsReview'], isA<bool>());
    expect(raw['needsReviewReasons'], isA<List<dynamic>>());
    expect(raw['source'], 'sms');
    expect(raw['createdAt'], isNotNull);
    expect(raw['deletedAt'], isNull);
    // Never leaks raw SMS content, sender, or a userId field — the
    // contract's core privacy guarantee.
    for (final forbiddenKey in [
      'body',
      'rawBody',
      'sender',
      'address',
      'userId',
      'candidateStatus',
    ]) {
      expect(
        raw.containsKey(forbiddenKey),
        isFalse,
        reason: '$forbiddenKey must never be written to Firestore',
      );
    }

    // --- 4. Conversion: real Transaction, source: 'sms' ---
    final created = await transactionRepository.createTransaction(
      type: TransactionType.expense,
      amount: localCandidate.amount,
      dateTime: localCandidate.transactionDate,
      accountId: accountId,
      categoryId: 'cat-shopping',
      description: localCandidate.merchant ?? '',
      source: 'sms',
    );
    expect(created.source, 'sms');

    final refreshedAccount = await accountRepository.getByKey(accountId);
    expect(
      refreshedAccount!.currentBalance,
      5000 - 1250.5,
      reason: 'the real balance-adjustment path must still run',
    );

    // --- 5. Immediate cloud cleanup + local consistency ---
    await linkSmsImportViaRepositories(
      inboxRepository: inboxRepository,
      memoryRepository: memoryRepository,
      smsId: smsItem.id,
      linkedEntityId: created.id,
      cloudCandidateRepository: cloudCandidateRepository,
    );

    final cloudAfterConvert = await cloudCandidateRepository.getAll();
    expect(
      cloudAfterConvert,
      isEmpty,
      reason:
          'the cloud candidate must be gone immediately, not just after the next scan()',
    );

    final smsAfterConvert = (await inboxRepository.getAll()).single;
    expect(smsAfterConvert.status, SmsImportStatus.imported);
    expect(smsAfterConvert.linkedEntityId, created.id);

    // A subsequent sync() must be a pure no-op — proves the immediate
    // delete and the deferred reconciler agree on the same end state.
    final syncAfterConvert = await cloudSync.sync();
    expect(syncAfterConvert.removed, 0);
    expect(syncAfterConvert.synced, 0);
    expect(await cloudCandidateRepository.getAll(), isEmpty);
  });

  test(
    'a Firestore outage during cleanup leaves local state consistent and self-heals on the next sync()',
    () async {
      final account = await accountRepository.createAccount(
        name: 'HDFC Savings',
        type: AccountType.bank,
        openingBalance: 5000,
        colorValue: 0xFF00FF00,
        bankId: 'hdfc',
        accountNumberLast4: '5623',
      );
      accountId = account.id;
      final matcher = AccountCardMatcher(
        accounts: [account],
        cards: const <CreditCardProfile>[],
      );

      final message = RawSmsMessage(
        address: 'VM-HDFCBK',
        body: 'Rs.500.00 debited from a/c XX5623 on 15-07-26.',
        date: DateTime(2026, 7, 15),
      );
      await scanAndBuildCandidates([message], matcher);
      final smsItem = (await inboxRepository.getAll()).single;
      final localCandidate = (await candidateDao.getBySmsItemId(smsItem.id))!;

      await cloudSync.sync();
      expect(await cloudCandidateRepository.getAll(), hasLength(1));

      final created = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: localCandidate.amount,
        dateTime: localCandidate.transactionDate,
        accountId: accountId,
        categoryId: 'cat-shopping',
        source: 'sms',
      );

      final throwingCloudRepository = _ThrowingDeleteRepository(
        cloudCandidateRepository.collection,
      );

      // The cleanup call fails outright (simulated outage) — must not throw
      // past this point, and local state must still fully reflect the
      // conversion.
      await expectLater(
        linkSmsImportViaRepositories(
          inboxRepository: inboxRepository,
          memoryRepository: memoryRepository,
          smsId: smsItem.id,
          linkedEntityId: created.id,
          cloudCandidateRepository: throwingCloudRepository,
        ),
        completes,
      );

      final smsAfterFailedCleanup = (await inboxRepository.getAll()).single;
      expect(
        smsAfterFailedCleanup.status,
        SmsImportStatus.imported,
        reason: 'local marking must not roll back on cloud failure',
      );
      expect(smsAfterFailedCleanup.linkedEntityId, created.id);

      // The stale cloud doc is still there (the immediate delete failed)...
      expect(await cloudCandidateRepository.getAll(), hasLength(1));

      // ...but the next full sync() self-heals it, because the SMS is no
      // longer pending — this is the safety net the immediate delete is
      // layered on top of, not a replacement for.
      final recoverySync = await cloudSync.sync();
      expect(recoverySync.removed, 1);
      expect(await cloudCandidateRepository.getAll(), isEmpty);
    },
  );
}

class _FakeReaderAdapter extends SmsReaderAdapter {
  _FakeReaderAdapter(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

/// Throws on every [deleteById] — stands in for Firestore being unreachable
/// at the exact moment of the post-convert cloud cleanup call.
class _ThrowingDeleteRepository extends SmsTransactionCandidateRepository {
  _ThrowingDeleteRepository(super.collection);

  @override
  Future<void> deleteById(String id) {
    throw Exception('simulated Firestore outage');
  }
}
