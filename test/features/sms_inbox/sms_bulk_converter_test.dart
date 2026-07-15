import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/sms_inbox/data/merchant_memory_dao.dart';
import 'package:finance_app/features/sms_inbox/data/merchant_memory_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_duplicate_reason.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_bulk_converter.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';
// sqflite exports its own `Transaction`, which collides with the app's.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

class _FakeSmsReaderAdapter extends SmsReaderAdapter {
  @override
  Future<List<RawSmsMessage>> readInbox() async => const [];
}

/// Bulk convert writes real transactions against real balances, so this
/// drives it through the *actual* `TransactionRepository` over a fake
/// Firestore rather than a stub. That's the point: it proves the loop reuses
/// the existing creation engine — including its account-balance math —
/// instead of reimplementing any part of it.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late SmsInboxRepository inboxRepository;
  late MerchantMemoryDao memoryDao;
  late TransactionRepository transactionRepository;
  late AccountRepository accountRepository;
  late SmsBulkConverter converter;
  late String accountId;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    inboxRepository = SmsInboxRepository(SmsInboxDao(database), _FakeSmsReaderAdapter());
    memoryDao = MerchantMemoryDao(database);

    final firestore = FakeFirebaseFirestore();

    final accountCollection = firestore.collection('accounts').withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    accountRepository = AccountRepository(accountCollection);

    final account = await accountRepository.createAccount(
      name: 'HDFC',
      type: AccountType.bank,
      openingBalance: 10000,
      colorValue: 0xFF00FF00,
    );
    accountId = account.id;

    final transactionCollection = firestore.collection('transactions').withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    transactionRepository = TransactionRepository(transactionCollection, accountRepository);

    converter = SmsBulkConverter(transactionRepository, inboxRepository, MerchantMemoryRepository(memoryDao));
  });

  tearDown(() async => database.database.close());

  SmsInboxItem smsItem({
    required String id,
    double? amount,
    String merchant = 'Amazon',
    String? duplicateOf,
  }) {
    final date = DateTime(2026, 7, 15, 12);
    return SmsInboxItem(
      id: id,
      messageKey: 'msg-$id',
      rawMessage: RawSmsMessage(address: 'VM-HDFCBK', body: 'body $id', date: date),
      dedupKey: 'dedup-$id',
      duplicateOfId: duplicateOf,
      duplicateReason: duplicateOf == null ? null : SmsDuplicateReason.sameReferenceNumber,
      status: SmsImportStatus.pending,
      createdAt: date,
      parsed: amount == null
          ? null
          : ParsedSmsTransaction(
              amount: amount,
              direction: SmsTransactionDirection.debit,
              dateTime: date,
              category: SmsTransactionCategory.cardPurchase,
              confidence: 0.9,
              rawBody: 'body $id',
              merchantOrSender: merchant,
            ),
    );
  }

  Future<List<SmsInboxItem>> seed(List<SmsInboxItem> items) async {
    final dao = SmsInboxDao(database);
    for (final item in items) {
      await dao.insertIfNew(item);
    }
    return items;
  }

  SmsBulkConvertConfig config({TransactionType type = TransactionType.expense}) => SmsBulkConvertConfig(
        type: type,
        categoryId: 'cat-shopping',
        accountId: accountId,
      );

  test('creates one independent transaction per SMS, never a merged lump sum', () async {
    final items = await seed([smsItem(id: 'a', amount: 100), smsItem(id: 'b', amount: 250)]);

    final result = await converter.convert(items, config());

    expect(result.converted, 2);
    final created = await transactionRepository.getAll();
    expect(created, hasLength(2));
    expect(created.map((t) => t.amount).toList()..sort(), [100, 250]);
  });

  test('applies the shared answers to every transaction', () async {
    final items = await seed([smsItem(id: 'a', amount: 100), smsItem(id: 'b', amount: 250)]);

    await converter.convert(items, config());

    final created = await transactionRepository.getAll();
    for (final transaction in created) {
      expect(transaction.accountId, accountId);
      expect(transaction.categoryId, 'cat-shopping');
      expect(transaction.type, TransactionType.expense);
    }
  });

  test('adjusts the account balance through the existing engine', () async {
    final items = await seed([smsItem(id: 'a', amount: 100), smsItem(id: 'b', amount: 250)]);

    await converter.convert(items, config());

    final account = await accountRepository.getByKey(accountId);
    // 10000 - 100 - 250. If this drifts, the loop is no longer reusing
    // createTransaction's balance math.
    expect(account?.currentBalance, 9650);
  });

  test('income adds to the balance rather than subtracting', () async {
    final items = await seed([smsItem(id: 'a', amount: 500)]);

    await converter.convert(items, config(type: TransactionType.income));

    final account = await accountRepository.getByKey(accountId);
    expect(account?.currentBalance, 10500);
  });

  test('marks every converted SMS imported and linked to its transaction', () async {
    final items = await seed([smsItem(id: 'a', amount: 100), smsItem(id: 'b', amount: 250)]);

    await converter.convert(items, config());

    final stored = await inboxRepository.getAll();
    expect(stored.every((item) => item.status == SmsImportStatus.imported), isTrue);
    expect(stored.every((item) => item.linkedEntityId != null), isTrue);
  });

  test('skips an SMS with no readable amount instead of inventing one', () async {
    final items = await seed([smsItem(id: 'a', amount: 100), smsItem(id: 'no-amount')]);

    final result = await converter.convert(items, config());

    expect(result.converted, 1);
    expect(result.skipped, 1);

    final created = await transactionRepository.getAll();
    expect(created, hasLength(1), reason: 'a zero-amount transaction must never be written');

    // The skipped one stays pending so the user can handle it manually.
    final stored = await inboxRepository.getAll();
    expect(stored.firstWhere((item) => item.id == 'no-amount').status, SmsImportStatus.pending);
  });

  test('learns the shared category once per conversion', () async {
    final items = await seed([smsItem(id: 'a', amount: 100), smsItem(id: 'b', amount: 250)]);

    await converter.convert(items, config());

    final memories = await memoryDao.getAll();
    expect(memories, hasLength(1));
    expect(memories.single.merchantKey, 'amazon');
    expect(memories.single.categoryId, 'cat-shopping');
    expect(memories.single.timesUsed, 2, reason: 'both conversions are real, counted decisions');
  });

  test('never bulk-converts a flagged duplicate, even if one is passed in', () async {
    // Duplicates are only convertible one at a time from the review sheet.
    // Converting one here would double-count a payment in real balances.
    final items = await seed([
      smsItem(id: 'a', amount: 100),
      smsItem(id: 'dupe', amount: 100, duplicateOf: 'a'),
    ]);

    final result = await converter.convert(items, config());

    expect(result.converted, 1);
    expect(result.skipped, 1);

    final created = await transactionRepository.getAll();
    expect(created, hasLength(1));

    final stored = await inboxRepository.getAll();
    expect(stored.firstWhere((item) => item.id == 'dupe').status, SmsImportStatus.pending);
  });

  test('a failed create leaves its SMS pending and does not stop the rest', () async {
    // A transaction against a deleted account is the realistic failure: the
    // create throws, and that message must stay convertible rather than be
    // marked imported against a record that was never written.
    final items = await seed([smsItem(id: 'a', amount: 100)]);
    final badConfig = SmsBulkConvertConfig(
      type: TransactionType.expense,
      categoryId: 'cat-shopping',
      accountId: 'account-that-does-not-exist',
    );

    final result = await converter.convert(items, badConfig);

    expect(result.failed, 1);
    expect(result.converted, 0);
    final stored = await inboxRepository.getAll();
    expect(stored.single.status, SmsImportStatus.pending);
    expect(stored.single.linkedEntityId, isNull);
  });
}
