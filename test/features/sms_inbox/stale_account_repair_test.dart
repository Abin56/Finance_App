import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/sms_inbox/data/financial_event_dao.dart';
import 'package:finance_app/features/sms_inbox/data/notification_capture_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/pending_candidate_generator.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_evidence_link.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
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

FinancialEvent _event({
  required String id,
  required String smsId,
  List<String> reasons = const [],
}) {
  return FinancialEvent(
    id: id,
    primarySmsItemId: smsId,
    eventType: FinancialEventType.payment,
    role: FinancialEventRole.standalone,
    status: FinancialEventStatus.pendingReview,
    direction: SmsTransactionDirection.debit,
    amount: const FieldConfidence(
      value: 350,
      confidence: 0.85,
      source: EvidenceSource.regexOnly,
    ),
    merchant: const FieldConfidence.unknown(),
    category: const FieldConfidence.unknown(),
    paymentMethod: const FieldConfidence<PaymentMethod>.unknown(),
    accountMatch: const FieldConfidence.unknown(),
    moneyMovement: const FieldConfidence(
      value: true,
      confidence: 0.85,
      source: EvidenceSource.regexOnly,
    ),
    transactionStatus: const FieldConfidence.unknown(),
    eventDate: DateTime(2026, 11, 1),
    overallConfidence: 0.3,
    confidenceLevel: ConfidenceLevel.low,
    automationAction: AutomationAction.needsReview,
    needsReview: true,
    reviewReasons: reasons,
    createdAt: DateTime(2026, 11, 1),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late TransactionCandidateDao candidateDao;
  late FinancialEventDao eventDao;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    candidateDao = TransactionCandidateDao(database);
    eventDao = FinancialEventDao(database);
  });

  tearDown(() async => database.database.close());

  final boiSms = RawSmsMessage(
    address: 'JX-BOIIND-S',
    body:
        'Rs.350.00 debited A/cXX9585 and credited to ABIN  JOHN via UPI Ref No 630557620611 on 01Nov26. Call 18001031906, if not done by you. -BOI',
    date: DateTime(2026, 11, 1, 16, 25),
  );

  final boiAccount = Account(
    id: 'boi-1',
    name: 'BOI Savings',
    type: AccountType.bank,
    openingBalance: 0,
    currentBalance: 0,
    colorValue: 0xFF000000,
    createdAt: DateTime(2026, 1, 1),
    bankId: 'boi',
    accountNumberLast4: '9585',
  );

  test('review reasons round-trip as separate sentences (not characters)', () async {
    await eventDao.upsert(
      _event(
        id: 'evt-1',
        smsId: 'sms-1',
        reasons: const [
          'No matching account or card found for this message.',
          'Merchant unknown.',
        ],
      ),
    );

    final loaded = await eventDao.getById('evt-1');

    expect(loaded!.reviewReasons, [
      'No matching account or card found for this message.',
      'Merchant unknown.',
    ]);
  });

  test(
    'a BOI SMS stored without a last-4 is repaired, rebuilt and matches the account',
    () async {
      final repository = SmsInboxRepository(
        SmsInboxDao(database),
        _FakeReader([boiSms]),
        notificationReader: _NoCaptured(),
      );
      await repository.scanInbox();

      // Simulate the row as the OLD parser stored it: no last-4, no bank.
      await database.database.update(SmsInboxDatabase.tableName, {
        'masked_account': null,
        'bank_name': null,
      });
      final item = (await SmsInboxDao(database).getAll()).single;
      expect(item.parsed!.maskedAccountOrCard, isNull);

      // Stale unmatched candidate + event, as already synced to the web.
      final stale = await generateMissingTransactionCandidates(
        inboxRepository: repository,
        dao: candidateDao,
        matcher: () =>
            AccountCardMatcher(accounts: [boiAccount], cards: const []),
      );
      expect(stale, 1);
      expect((await candidateDao.getAll()).single.matchedAccountId, isNull);
      await eventDao.upsert(_event(id: 'evt-1', smsId: item.id));
      await eventDao.linkSms(
        FinancialEventEvidenceLink(
          id: 'link-1',
          financialEventId: 'evt-1',
          smsItemId: item.id,
          linkType: FinancialEventLinkType.newEvent,
          confidence: 0.3,
          linkedAt: DateTime(2026, 11, 1),
        ),
      );

      final repaired = await repairStaleAccountFields(
        inboxRepository: repository,
        candidateDao: candidateDao,
        eventDao: eventDao,
      );

      expect(repaired, 1);
      final fixed = (await SmsInboxDao(database).getAll()).single;
      expect(fixed.parsed!.maskedAccountOrCard, '9585');
      expect(fixed.parsed!.bankName, 'Bank of India');
      expect(await candidateDao.getAll(), isEmpty);
      expect(await eventDao.getById('evt-1'), isNull);
      expect(await eventDao.smsItemIdsWithLinks(), isEmpty);

      final rebuilt = await generateMissingTransactionCandidates(
        inboxRepository: repository,
        dao: candidateDao,
        matcher: () =>
            AccountCardMatcher(accounts: [boiAccount], cards: const []),
      );
      expect(rebuilt, 1);
      expect((await candidateDao.getAll()).single.matchedAccountId, 'boi-1');

      // Idempotent: nothing left to repair on the next run.
      expect(
        await repairStaleAccountFields(
          inboxRepository: repository,
          candidateDao: candidateDao,
          eventDao: eventDao,
        ),
        0,
      );
    },
  );

  test(
    'a candidate built before the account existed is re-matched later',
    () async {
      final repository = SmsInboxRepository(
        SmsInboxDao(database),
        _FakeReader([boiSms]),
        notificationReader: _NoCaptured(),
      );
      await repository.scanInbox();

      // Built while the user's accounts were empty / not yet loaded.
      await generateMissingTransactionCandidates(
        inboxRepository: repository,
        dao: candidateDao,
        matcher: () => AccountCardMatcher(accounts: const [], cards: const []),
      );
      expect((await candidateDao.getAll()).single.matchedAccountId, isNull);

      var matcherCalls = 0;
      final fixed = await repairStaleAccountFields(
        inboxRepository: repository,
        candidateDao: candidateDao,
        eventDao: eventDao,
        matcher: () {
          matcherCalls++;
          return AccountCardMatcher(accounts: [boiAccount], cards: const []);
        },
      );

      expect(fixed, 1);
      expect((await candidateDao.getAll()).single.matchedAccountId, 'boi-1');

      // Matched now: a second run does nothing and never reads accounts.
      expect(
        await repairStaleAccountFields(
          inboxRepository: repository,
          candidateDao: candidateDao,
          eventDao: eventDao,
          matcher: () {
            matcherCalls++;
            return AccountCardMatcher(accounts: [boiAccount], cards: const []);
          },
        ),
        0,
      );
      expect(matcherCalls, 1);
    },
  );

  test('a still-unmatched candidate is left alone when nothing resolves', () async {
    final repository = SmsInboxRepository(
      SmsInboxDao(database),
      _FakeReader([boiSms]),
      notificationReader: _NoCaptured(),
    );
    await repository.scanInbox();
    await generateMissingTransactionCandidates(
      inboxRepository: repository,
      dao: candidateDao,
      matcher: () => AccountCardMatcher(accounts: const [], cards: const []),
    );
    final before = (await candidateDao.getAll()).single.id;

    final fixed = await repairStaleAccountFields(
      inboxRepository: repository,
      candidateDao: candidateDao,
      matcher: () => AccountCardMatcher(accounts: const [], cards: const []),
    );

    expect(fixed, 0);
    expect((await candidateDao.getAll()).single.id, before);
  });

  test('repair never touches a row that already has a last-4', () async {
    final repository = SmsInboxRepository(
      SmsInboxDao(database),
      _FakeReader([boiSms]),
      notificationReader: _NoCaptured(),
    );
    await repository.scanInbox();

    expect(
      await repairStaleAccountFields(
        inboxRepository: repository,
        candidateDao: candidateDao,
        eventDao: eventDao,
      ),
      0,
    );
  });
}
