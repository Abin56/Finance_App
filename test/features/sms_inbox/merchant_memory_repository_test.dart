import 'package:finance_app/features/sms_inbox/data/merchant_memory_dao.dart';
import 'package:finance_app/features/sms_inbox/data/merchant_memory_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late MerchantMemoryRepository repository;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    repository = MerchantMemoryRepository(MerchantMemoryDao(database));
  });

  tearDown(() async => database.database.close());

  test('records a decision under the normalized merchant key', () async {
    await repository.record(
      merchant: 'UPI-SWIGGY*ORDER-12345',
      transactionType: TransactionType.expense,
      categoryId: 'cat-food',
    );

    final memories = await repository.getAll();
    expect(memories, hasLength(1));
    expect(memories.single.merchantKey, 'swiggy order');
    expect(memories.single.categoryId, 'cat-food');
    expect(memories.single.timesUsed, 1);
  });

  test('repeating a choice bumps the count instead of duplicating the row', () async {
    for (var i = 0; i < 3; i++) {
      await repository.record(
        merchant: 'Amazon',
        transactionType: TransactionType.expense,
        categoryId: 'cat-shopping',
      );
    }

    final memories = await repository.getAll();
    expect(memories, hasLength(1));
    expect(memories.single.timesUsed, 3);
  });

  test('a different category for the same merchant is its own counted row', () async {
    await repository.record(merchant: 'Amazon', transactionType: TransactionType.expense, categoryId: 'cat-shopping');
    await repository.record(merchant: 'Amazon', transactionType: TransactionType.expense, categoryId: 'cat-food');

    final memories = await repository.getAll();
    expect(memories, hasLength(2), reason: 'the suggester needs both to rank a changed mind');
  });

  test('the same merchant on each side of the ledger stays separate', () async {
    await repository.record(merchant: 'Amazon', transactionType: TransactionType.expense, categoryId: 'cat-shopping');
    await repository.record(merchant: 'Amazon', transactionType: TransactionType.income, categoryId: 'cat-refund');

    final memories = await repository.getAll();
    expect(memories, hasLength(2));
  });

  test('records nothing when the merchant normalizes to nothing', () async {
    // An empty key would collide every unidentifiable merchant into one
    // bucket that then recalls an unrelated category for all of them.
    await repository.record(merchant: '  ', transactionType: TransactionType.expense, categoryId: 'cat-food');
    await repository.record(merchant: null, transactionType: TransactionType.expense, categoryId: 'cat-food');

    expect(await repository.getAll(), isEmpty);
  });
}
