import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/data/financial_event_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/category_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'evaluation/sms_evaluation_harness.dart';
import 'fixtures/sms_test_case.dart';
import 'fixtures/sms_test_corpus.dart';

/// Corpus-driven evaluation of FlowFi's SMS financial-classification
/// pipeline (`SmsFinancialFilter` -> `SmsParserRegistry` ->
/// `FinancialEventExtractor`), run in regex-only mode (no AI provider — see
/// [SmsEvaluationHarness] doc comment for why). This is not meant to
/// duplicate the field-by-field assertions already covered by
/// `financial_event_classification_test.dart` and `transaction_matcher_test.dart`;
/// its job is:
///
/// 1. Provide one growing, structured corpus (`sms_test_corpus.dart`) that
///    future cases — including ones targeting the AI-assisted path once a
///    live/fake provider is wired up — get added to, rather than scattered
///    across ad hoc `test()` blocks.
/// 2. Print an aggregate scorecard so a human can see overall accuracy at a
///    glance, not just a pass/fail bit per case.
/// 3. Fail loudly and specifically on any case marked
///    [SmsTestCase.isDangerousIfMisclassified] — a wrong money-movement
///    verdict is the one class of bug this whole system exists to prevent.
void main() {
  // Sections of the corpus that need bespoke per-case setup (a specific
  // AccountCardMatcher, or a real FinancialEventDao/TransactionMatcher) are
  // excluded from the generic sweep below and evaluated in their own groups.
  final bespokeIds = {
    'own-account-transfer-01',
    'external-transfer-not-own-01',
    'dup-same-reference-01a',
    'dup-same-reference-01b',
    ...categoryVariationIds,
    ...phase5OwnAccountTransferIds,
  };
  final genericCases = smsTestCorpus
      .where((c) => !bespokeIds.contains(c.id))
      .toList();

  group('SMS corpus evaluation (generic cases, regex-only)', () {
    const harness = SmsEvaluationHarness();
    late SmsEvaluationReport report;

    setUpAll(() async {
      report = await harness.evaluateAll(genericCases);
      // Always visible in test output — this is the point of the corpus.
      // ignore: avoid_print
      print(report.summary());
    });

    test('no case marked dangerous is misclassified', () {
      expect(
        report.dangerousMismatches,
        isEmpty,
        reason:
            'A dangerous misclassification means FlowFi got the money-movement '
            'verdict wrong on a case explicitly flagged safety-critical — see '
            'the printed report above for which case(s) and why.',
      );
    });

    test('overall pass rate meets the regex-only baseline bar', () {
      // Some coarser-without-AI cases (e.g. credit-card-bill-payment-01) are
      // intentionally not perfect matches for every field; the bar here is
      // "the deterministic layer is not silently regressing", not "100%".
      expect(
        report.passRate,
        greaterThanOrEqualTo(0.9),
        reason: report.summary(),
      );
    });

    for (final testCase in genericCases) {
      test(
        '[${testCase.id}] ${testCase.explanation}',
        () async {
          final result = await harness.evaluate(testCase);
          expect(
            result.mismatches,
            isEmpty,
            reason: '"${testCase.body}"\n  ${result.mismatches.join('\n  ')}',
          );
        },
        skip: testCase.knownIssue == null
            ? false
            : 'known issue, not fixed by this session: ${testCase.knownIssue}',
      );
    }
  });

  group(
    'SMS corpus evaluation (own-account transfer, needs a real matcher)',
    () {
      const harness = SmsEvaluationHarness();

      Account account(String id, String last4) => Account(
        id: id,
        name: 'Account $id',
        type: AccountType.bank,
        openingBalance: 0,
        currentBalance: 0,
        colorValue: 0xFF000000,
        createdAt: DateTime(2026, 1, 1),
        accountNumberLast4: last4,
      );

      final matcher = AccountCardMatcher(
        accounts: [account('acc-1', '1234'), account('acc-2', '9876')],
        cards: const [],
      );

      for (final id in [
        'own-account-transfer-01',
        'external-transfer-not-own-01',
        ...phase5OwnAccountTransferIds,
      ]) {
        final testCase = smsTestCorpus.firstWhere((c) => c.id == id);
        test('[${testCase.id}] ${testCase.explanation}', () async {
          final result = await harness.evaluate(
            testCase,
            accountCardMatcher: matcher,
          );
          expect(
            result.mismatches,
            isEmpty,
            reason: result.mismatches.join('\n'),
          );
        });
      }
    },
  );

  group(
    'SMS corpus evaluation (category variations, needs a real categories list + CategoryResolver)',
    () {
      // The generic sweep above runs with `categories: const []` and no
      // `CategoryResolver` at all, so category resolution never fires there
      // — this group exists specifically to exercise it, using a small
      // "user's real categories" fixture whose names line up with
      // `MerchantSeedCatalog`'s and `MerchantCategorySuggester._fromSmsCategory`'s
      // candidate names.
      Category category(String id, String name) => Category(
        id: id,
        name: name,
        type: CategoryType.expense,
        iconKey: 'category',
        colorValue: 0xFF000000,
        createdAt: DateTime(2026, 1, 1),
      );
      final categories = [
        category('cat-food-dining', 'Food & Dining'),
        category('cat-groceries', 'Groceries'),
        category('cat-shopping', 'Shopping'),
        category('cat-transport', 'Transport'),
        category('cat-fuel', 'Fuel'),
        category('cat-entertainment', 'Entertainment'),
        category('cat-subscriptions', 'Subscriptions'),
        category('cat-bills-utilities', 'Bills & Utilities'),
        category('cat-health', 'Health'),
        category('cat-salary', 'Salary'),
        category('cat-other', 'Other'),
      ];
      final harness = SmsEvaluationHarness(
        extractor: FinancialEventExtractor(
          categoryResolver: CategoryResolver(
            const MerchantCategorySuggester([]),
          ),
        ),
      );

      for (final id in categoryVariationIds) {
        final testCase = smsTestCorpus.firstWhere((c) => c.id == id);
        test('[${testCase.id}] ${testCase.explanation}', () async {
          final result = await harness.evaluate(
            testCase,
            categories: categories,
          );
          expect(
            result.mismatches,
            isEmpty,
            reason: '"${testCase.body}"\n  ${result.mismatches.join('\n  ')}',
          );
        });
      }
    },
  );

  group(
    'SMS corpus evaluation (duplicate/linking seeds, via TransactionMatcher)',
    () {
      setUpAll(() {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      });

      late SmsInboxDatabase database;
      late FinancialEventDao dao;
      late TransactionMatcher matcher;
      const harness = SmsEvaluationHarness();

      setUp(() async {
        SmsInboxDatabase.debugReset();
        database = await SmsInboxDatabase.openInMemoryForTest();
        dao = FinancialEventDao(database);
        matcher = TransactionMatcher(dao);
      });

      tearDown(() async {
        await database.database.close();
      });

      test(
        'two SMS confirming the same underlying transfer (shared reference '
        'number) must resolve as the same event, not a duplicate spend',
        () async {
          final first = smsTestCorpus.firstWhere(
            (c) => c.id == 'dup-same-reference-01a',
          );
          final second = smsTestCorpus.firstWhere(
            (c) => c.id == 'dup-same-reference-01b',
          );

          final firstResult = await harness.evaluate(first);
          expect(firstResult.event, isNotNull, reason: 'first SMS must parse');
          final firstOutcome = await matcher.match(firstResult.event!);
          expect(
            firstOutcome.result,
            FinancialEventMatchResult.newEvent,
            reason: 'the first sighting of this transfer must be a new event',
          );
          await dao.upsert(firstResult.event!);

          final secondResult = await harness.evaluate(second);
          expect(
            secondResult.event,
            isNotNull,
            reason: 'second SMS must parse',
          );
          final secondOutcome = await matcher.match(secondResult.event!);
          expect(
            secondOutcome.result,
            isNot(FinancialEventMatchResult.newEvent),
            reason:
                'a second confirmation SMS sharing the same reference number '
                'must never be treated as an independent second transaction — '
                'that would double-count real spending',
          );
        },
      );
    },
  );

  test('corpus sanity: no duplicate ids', () {
    final ids = smsTestCorpus.map((c) => c.id).toList();
    expect(
      ids.toSet().length,
      ids.length,
      reason: 'every SmsTestCase.id must be unique',
    );
  });

  test(
    'corpus sanity: reminder-type cases are consistently marked dangerous',
    () {
      final reminderCases = smsTestCorpus.where(
        (c) => c.expected.eventType == FinancialEventType.reminder,
      );
      for (final c in reminderCases) {
        expect(
          c.isDangerousIfMisclassified,
          isTrue,
          reason:
              '[${c.id}] a reminder case should be marked isDangerousIfMisclassified',
        );
      }
    },
  );
}
