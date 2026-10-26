import 'package:finance_app/features/sms_inbox/data/notification_capture_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/pending_candidate_generator.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeReader extends SmsReaderAdapter {
  _FakeReader(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

class _NoCaptured extends NotificationCaptureAdapter {
  @override
  Future<List<RawSmsMessage>> readCaptured() async => const [];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late TransactionCandidateDao candidateDao;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    candidateDao = TransactionCandidateDao(database);
  });

  tearDown(() async => database.database.close());

  final bankSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body:
        'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );

  Future<SmsInboxRepository> scanned(List<RawSmsMessage> sms) async {
    final repository = SmsInboxRepository(
      SmsInboxDao(database),
      _FakeReader(sms),
      notificationReader: _NoCaptured(),
    );
    await repository.scanInbox();
    return repository;
  }

  AccountCardMatcher emptyMatcher() =>
      AccountCardMatcher(accounts: const [], cards: const []);

  test('builds one candidate for a new pending parsed SMS', () async {
    final repository = await scanned([bankSms]);

    final built = await generateMissingTransactionCandidates(
      inboxRepository: repository,
      dao: candidateDao,
      matcher: emptyMatcher,
    );

    expect(built, 1);
    final candidates = await candidateDao.getAll();
    expect(candidates.single.amount, 1250.0);
  });

  test('a second run builds nothing and never reads accounts', () async {
    final repository = await scanned([bankSms]);
    await generateMissingTransactionCandidates(
      inboxRepository: repository,
      dao: candidateDao,
      matcher: emptyMatcher,
    );

    var matcherCalls = 0;
    final built = await generateMissingTransactionCandidates(
      inboxRepository: repository,
      dao: candidateDao,
      matcher: () {
        matcherCalls++;
        return emptyMatcher();
      },
    );

    expect(built, 0);
    expect(matcherCalls, 0);
    expect(await candidateDao.getAll(), hasLength(1));
  });

  test('a failed account read writes no candidates', () async {
    final repository = await scanned([bankSms]);

    await expectLater(
      generateMissingTransactionCandidates(
        inboxRepository: repository,
        dao: candidateDao,
        matcher: () async => throw Exception('offline'),
      ),
      throwsException,
    );

    expect(await candidateDao.getAll(), isEmpty);
  });
}
