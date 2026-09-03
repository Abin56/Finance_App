// FlowFi SMS Intelligence Benchmark — Phase 6 Foundation.
//
// Aggregates the EXISTING production evaluation corpora (built by prior
// Phase 4/5 sessions under test/features/sms_inbox/financial_event/**) into
// the Part 18 report format, and computes real per-field accuracy numbers
// by parsing the harnesses' own mismatch strings (each mismatch line is
// `"<field>: expected X but got Y"`, produced by the real production
// pipeline — FinancialEventExtractor, FinancialEventConfidenceEngine,
// TransactionMatcher, ObligationClassifier, EventRelationshipEngine — never
// a reimplementation).
//
// This file does NOT define new SMS cases. It intentionally reuses the
// corpora already reviewed and passing under test/, because that corpus
// already satisfies FLOWFI Phase 6 Parts 1-11/15 (250+ high-quality,
// semantically varied, adversarial, multi-bank/provider/merchant cases with
// explicit expected values and dangerous-misclassification flags). Building
// a second, competing corpus here would fork ground truth rather than
// benchmark the real system.
//
// Run with:
//   flutter test benchmark/flowfi_sms_benchmark_test.dart
import 'dart:io';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/category_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/features/sms_inbox/financial_event/evaluation/sms_evaluation_harness.dart';
import '../test/features/sms_inbox/financial_event/fixtures/sms_test_corpus.dart';
import '../test/features/sms_inbox/financial_event/linking/evaluation/linking_evaluation_harness.dart';
import '../test/features/sms_inbox/financial_event/linking/fixtures/linking_test_corpus.dart';
import '../test/features/sms_inbox/financial_event/obligation/evaluation/obligation_evaluation_harness.dart';
import '../test/features/sms_inbox/financial_event/obligation/fixtures/obligation_test_corpus.dart';
import 'fixtures/benchmark_categories.dart';

/// Per-field accuracy tracker: counts how many cases *specified* an
/// expectation for a field (mismatch string starts with "<field>:") and how
/// many of those were correct (no mismatch line for that field).
class _FieldStats {
  final Map<String, int> specified = {};
  final Map<String, int> correct = {};

  void record(String field, bool wasCorrect) {
    specified[field] = (specified[field] ?? 0) + 1;
    if (wasCorrect) correct[field] = (correct[field] ?? 0) + 1;
  }

  String pct(String field) {
    final s = specified[field] ?? 0;
    if (s == 0) return 'n/a (0 cases)';
    final c = correct[field] ?? 0;
    return '${(c / s * 100).toStringAsFixed(1)}% ($c/$s)';
  }
}

void main() {
  test(
    'FlowFi SMS Intelligence Benchmark — full report (Phase 6 Foundation)',
    () async {
      final buffer = StringBuffer();
      void w(String s) {
        buffer.writeln(s);
      }

      // ---------------------------------------------------------------
      // 1. Run the main SMS corpus (regex-only pipeline, no AI provider —
      //    the honest baseline every user gets when AI is off/unavailable).
      //    Mirrors sms_corpus_evaluation_test.dart's exact three-way split:
      //    generic cases (no bespoke setup), own-account-transfer cases
      //    (need a real AccountCardMatcher), and category-variation cases
      //    (need a real categories list + CategoryResolver) — running every
      //    case through the bare default harness (as a first pass did)
      //    understates accuracy on those two bespoke groups, since category
      //    resolution and own-account matching never fire without them.
      // ---------------------------------------------------------------
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
      final ownTransferMatcher = AccountCardMatcher(
        accounts: [account('acc-1', '1234'), account('acc-2', '9876')],
        cards: const [],
      );
      final categoryHarness = SmsEvaluationHarness(
        extractor: FinancialEventExtractor(
          categoryResolver: CategoryResolver(const MerchantCategorySuggester([])),
        ),
      );

      final bespokeIds = {
        'own-account-transfer-01',
        'external-transfer-not-own-01',
        'dup-same-reference-01a',
        'dup-same-reference-01b',
        ...categoryVariationIds,
        ...phase5OwnAccountTransferIds,
      };
      final ownTransferIds = {
        'own-account-transfer-01',
        'external-transfer-not-own-01',
        ...phase5OwnAccountTransferIds,
      };
      final genericCases = smsTestCorpus
          .where((c) => !bespokeIds.contains(c.id))
          .toList();
      final ownTransferCases = smsTestCorpus
          .where((c) => ownTransferIds.contains(c.id))
          .toList();
      final categoryCases = smsTestCorpus
          .where((c) => categoryVariationIds.contains(c.id))
          .toList();

      final genericReport = await harness.evaluateAll(genericCases);
      final ownTransferResults = [
        for (final c in ownTransferCases)
          await harness.evaluate(c, accountCardMatcher: ownTransferMatcher),
      ];
      final categoryResults = [
        for (final c in categoryCases)
          await categoryHarness.evaluate(c, categories: benchmarkCategories),
      ];
      final smsReport = SmsEvaluationReport([
        ...genericReport.results,
        ...ownTransferResults,
        ...categoryResults,
      ]);

      // Per-field accuracy: walk every case's mismatches, but a case only
      // "specifies" a field if its ExpectedFinancialClassification set a
      // non-null value for it (approximated here by scanning the mismatch
      // list's field prefixes plus a positive count for every case with no
      // mismatch in that family — see fieldsChecked below).
      final fieldStats = _FieldStats();
      for (final r in smsReport.results) {
        if (r.isKnownIssue) continue;
        final expected = r.testCase.expected;
        final specifiedFields = <String>{
          if (expected.moneyMovement != null) 'moneyMovement',
          if (expected.direction != null) 'direction',
          if (expected.amount != null) 'amount',
          if (expected.eventType != null) 'eventType',
          if (expected.transactionStatus != null) 'transactionStatus',
          if (expected.paymentMethod != null) 'paymentMethod',
          if (expected.merchantEquals != null ||
              expected.merchantContains != null ||
              expected.merchantIsNull == true)
            'merchant',
          if (expected.merchantType != null ||
              expected.merchantTypeIsNull == true)
            'merchantType',
          if (expected.paymentProvider != null ||
              expected.paymentProviderIsNull == true)
            'paymentProvider',
          if (expected.categoryNameEquals != null ||
              expected.categoryIsNull == true)
            'category',
          if (expected.isOwnAccountTransfer != null) 'isOwnAccountTransfer',
          if (expected.referenceNumberIsNull == true) 'referenceNumber',
        };
        for (final f in specifiedFields) {
          final hasMismatch = r.mismatches.any((m) => m.startsWith('$f:'));
          fieldStats.record(f, !hasMismatch);
        }
      }

      // ---------------------------------------------------------------
      // 2. Run the Phase 5 linking/relationship corpus (multi-SMS
      //    lifecycle sequences, duplicate/refund/reversal, own-transfer).
      // ---------------------------------------------------------------
      const linkingHarness = LinkingEvaluationHarness();
      final linkingReport = await linkingHarness.evaluateAll(
        linkingTestCorpus,
      );

      // ---------------------------------------------------------------
      // 3. Run the Phase 4 obligation corpus (EMI/bills/subscriptions/rent
      //    lifecycle: reminder -> upcoming -> due -> successful/failed).
      // ---------------------------------------------------------------
      const obligationHarness = ObligationEvaluationHarness();
      final obligationReport = obligationHarness.evaluateAll(
        obligationTestCorpus,
      );

      // ---------------------------------------------------------------
      // Report
      // ---------------------------------------------------------------
      w('FLOWFI SMS INTELLIGENCE BENCHMARK');
      w('Generated: ${DateTime.now().toUtc().toIso8601String()}');
      w('');
      final totalCases =
          smsReport.total + linkingReport.total + obligationReport.total;
      w(
        'Total cases: $totalCases '
        '(classification corpus: ${smsReport.total}, '
        'relationship/linking corpus: ${linkingReport.total}, '
        'obligation corpus: ${obligationReport.total})',
      );
      w('');
      w('--- Classification corpus (${smsReport.total} cases) ---');
      w(
        'Case pass rate: ${(smsReport.passRate * 100).toStringAsFixed(1)}% '
        '(${smsReport.passedCount}/${smsReport.total}, '
        '${smsReport.knownIssues.length} known-issue case(s) graded but excluded from pass/fail)',
      );
      w('Event classification (eventType): ${fieldStats.pct('eventType')}');
      w('Money movement / direction: ${fieldStats.pct('direction')}');
      w('Amount: ${fieldStats.pct('amount')}');
      w('Merchant: ${fieldStats.pct('merchant')}');
      w('Merchant type: ${fieldStats.pct('merchantType')}');
      w('Payment provider: ${fieldStats.pct('paymentProvider')}');
      w('Category: ${fieldStats.pct('category')}');
      w('Payment method: ${fieldStats.pct('paymentMethod')}');
      w('Transaction status: ${fieldStats.pct('transactionStatus')}');
      w('Own-account transfer flag: ${fieldStats.pct('isOwnAccountTransfer')}');
      w('Reference number (never-invented guard): ${fieldStats.pct('referenceNumber')}');
      w('');
      w('--- Relationship / linking corpus (${linkingReport.total} cases) ---');
      w(
        'Relationship linking accuracy: '
        '${(linkingReport.passRate * 100).toStringAsFixed(1)}% '
        '(${linkingReport.passedCount}/${linkingReport.total}, '
        '${linkingReport.knownIssues.length} known-issue case(s))',
      );
      w('');
      w('--- Obligation corpus (${obligationReport.total} cases) ---');
      w(
        'Obligation detection accuracy: '
        '${(obligationReport.passRate * 100).toStringAsFixed(1)}% '
        '(${obligationReport.passedCount}/${obligationReport.total}, '
        '${obligationReport.knownIssues.length} known-issue case(s))',
      );
      w('');

      final dangerousFP = <String>[];
      final dangerousFN = <String>[];
      for (final r in smsReport.dangerousMismatches) {
        final wentToTrue = r.event?.moneyMovement.value == true;
        (wentToTrue ? dangerousFP : dangerousFN).add(r.testCase.id);
      }
      final dangerousTotal =
          smsReport.dangerousMismatches.length +
          linkingReport.dangerousMismatches.length +
          obligationReport.dangerousMismatches.length;

      w(
        'Dangerous false positives (reminder/failed/pending/refund/reversal/'
        'transfer/cashback wrongly treated as a completed inbound/outbound '
        'transaction): ${dangerousFP.length}',
      );
      w(
        'Dangerous false negatives (a real completed transaction wrongly '
        'suppressed as a reminder/non-event): ${dangerousFN.length}',
      );
      w(
        'Dangerous mismatches in linking/obligation corpora: '
        '${linkingReport.dangerousMismatches.length + obligationReport.dangerousMismatches.length}',
      );
      w('Total dangerous cases evaluated across all corpora: '
          '${smsReport.results.where((r) => r.testCase.isDangerousIfMisclassified).length + linkingReport.results.where((r) => r.testCase.isDangerousIfMisclassified).length + obligationReport.results.where((r) => r.testCase.isDangerousIfMisclassified).length}');
      w('');
      w(
        'Overall safety status: '
        '${dangerousTotal == 0 ? "SAFE (0 dangerous misclassifications across all corpora)" : "REVIEW ($dangerousTotal dangerous misclassification(s) found)"}',
      );
      w('');

      w('=== Known issues (documented gaps, NOT production fixes) ===');
      for (final r in smsReport.knownIssues) {
        w('  [sms:${r.testCase.id}] ${r.testCase.knownIssue}');
      }
      for (final r in linkingReport.knownIssues) {
        w('  [linking:${r.testCase.id}] ${r.testCase.knownIssue}');
      }
      for (final r in obligationReport.knownIssues) {
        w('  [obligation:${r.testCase.id}] ${r.testCase.knownIssue}');
      }
      w('');
      w(buffer.isEmpty ? '' : '');

      final output = buffer.toString();
      // Print to the flutter test console (visible via -r expanded / plain).
      // ignore: avoid_print
      print(output);

      // Persist alongside REPORT.md so a human/CI can diff numbers over time.
      try {
        File(
          'benchmark/last_run_output.txt',
        ).writeAsStringSync(output);
      } catch (_) {
        // Best effort only — some CI sandboxes disallow filesystem writes;
        // the console `print` above is the source of truth either way.
      }

      // Safety invariant — this is the one hard assertion in this file: no
      // dangerous misclassification anywhere in any corpus. If a prior
      // session's fix regresses, this benchmark goes red immediately.
      expect(
        dangerousTotal,
        0,
        reason:
            'A dangerous misclassification appeared in the benchmark run — '
            'see printed report above for which case(s).',
      );
    },
  );
}
