import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/sms_inbox/domain/account_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_confidence_engine.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser_registry.dart';

import '../fixtures/sms_test_case.dart';

/// The outcome of running one [SmsTestCase] through the real pipeline
/// (`SmsFinancialFilter` -> `SmsParserRegistry` -> [FinancialEventExtractor])
/// and comparing the result field-by-field against
/// [SmsTestCase.expected].
class SmsCaseResult {
  const SmsCaseResult({
    required this.testCase,
    required this.mismatches,
    required this.event,
    this.overallConfidence,
    this.confidenceLevel,
  });

  final SmsTestCase testCase;

  /// Part 14 (confidence calibration) — the real
  /// `FinancialEventConfidenceEngine` score for [event] (the harness runs
  /// it exactly as the production pipeline does — see
  /// `SmsEvaluationHarness.evaluate` — rather than leaving
  /// [FinancialEvent.overallConfidence]'s neutral placeholder value in
  /// place), so a human can later ask "when the system says High
  /// confidence, how often is it actually correct?" against [passed]. Null
  /// when [event] itself is null (the case never reached the extractor).
  final double? overallConfidence;
  final ConfidenceLevel? confidenceLevel;

  /// Per-field confidences straight off [event] — same calibration
  /// purpose as [overallConfidence], at finer grain. Deliberately just a
  /// read of existing [FieldConfidence]s — this collects evidence, it does
  /// not change what those confidences mean or how they're computed.
  Map<String, double?> get fieldConfidences => {
    'amount': event?.amount.confidence,
    'merchant': event?.merchant.confidence,
    'category': event?.category.confidence,
    'paymentProvider': event?.paymentProvider.confidence,
    'merchantType': event?.merchantType.confidence,
    'accountMatch': event?.accountMatch.confidence,
    'moneyMovement': event?.moneyMovement.confidence,
    'transactionStatus': event?.transactionStatus.confidence,
  };

  bool get needsReview => event?.needsReview ?? false;
  List<String> get reviewReasons => event?.reviewReasons ?? const [];

  /// Human-readable `"field: expected X but got Y"` lines — empty means a
  /// full pass. Only fields the case actually specified are checked, so an
  /// empty list here means every *specified* expectation held, not that
  /// every possible field matched.
  final List<String> mismatches;

  /// The event actually produced, or `null` when the case expected (and got)
  /// rejection before parsing (e.g. non-financial noise), or when parsing
  /// was expected to fail.
  final FinancialEvent? event;

  /// A case with a [SmsTestCase.knownIssue] is graded (mismatches are still
  /// computed and shown) but never counted as a pass/fail in aggregate
  /// scoring — it's a confirmed, already-reported gap, not a fresh signal.
  bool get isKnownIssue => testCase.knownIssue != null;

  bool get passed => mismatches.isEmpty || isKnownIssue;

  /// True only when this case is marked [SmsTestCase.isDangerousIfMisclassified]
  /// AND it failed — i.e. not just any failure, but specifically one where a
  /// wrong verdict could mislead a user about whether money actually moved.
  /// A known issue is never counted as dangerous here — see
  /// [SmsTestCase.knownIssue] for why it's graded separately.
  bool get isDangerousMismatch =>
      !isKnownIssue &&
      mismatches.isNotEmpty &&
      testCase.isDangerousIfMisclassified;
}

/// Aggregate report over a whole corpus run — printed by
/// `sms_corpus_evaluation_test.dart` so a human reading test output sees a
/// scorecard, not just a pass/fail bit.
class SmsEvaluationReport {
  const SmsEvaluationReport(this.results);

  final List<SmsCaseResult> results;

  int get total => results.length;
  int get passedCount => results.where((r) => r.passed).length;
  int get failedCount => total - passedCount;
  List<SmsCaseResult> get failures => results.where((r) => !r.passed).toList();
  List<SmsCaseResult> get dangerousMismatches =>
      results.where((r) => r.isDangerousMismatch).toList();
  List<SmsCaseResult> get knownIssues =>
      results.where((r) => r.isKnownIssue).toList();

  double get passRate => total == 0 ? 1.0 : passedCount / total;

  String summary() {
    final buffer = StringBuffer();
    buffer.writeln('=== SMS Evaluation Report ===');
    buffer.writeln(
      'Total: $total   Passed: $passedCount   Failed: $failedCount   '
      'Pass rate: ${(passRate * 100).toStringAsFixed(1)}%',
    );
    if (dangerousMismatches.isNotEmpty) {
      buffer.writeln(
        '\n!!! ${dangerousMismatches.length} DANGEROUS misclassification(s) — money-movement verdict is wrong on a case marked safety-critical !!!',
      );
      for (final r in dangerousMismatches) {
        buffer.writeln('  [${r.testCase.id}] "${r.testCase.body}"');
        buffer.writeln('    why this matters: ${r.testCase.explanation}');
        for (final m in r.mismatches) {
          buffer.writeln('    - $m');
        }
      }
    }
    final ordinaryFailures = failures
        .where((r) => !r.testCase.isDangerousIfMisclassified && !r.isKnownIssue)
        .toList();
    if (ordinaryFailures.isNotEmpty) {
      buffer.writeln('\nOther failures:');
      for (final r in ordinaryFailures) {
        buffer.writeln('  [${r.testCase.id}] "${r.testCase.body}"');
        for (final m in r.mismatches) {
          buffer.writeln('    - $m');
        }
      }
    }
    if (knownIssues.isNotEmpty) {
      buffer.writeln(
        '\n${knownIssues.length} known issue(s) (confirmed gaps, graded but not counted as failures):',
      );
      for (final r in knownIssues) {
        buffer.writeln('  [${r.testCase.id}] ${r.testCase.knownIssue}');
      }
    }
    buffer.write(calibrationSummary());
    return buffer.toString();
  }

  /// Part 14 — confidence calibration data: for each [ConfidenceLevel] the
  /// engine actually assigned, how many of those cases *passed* their
  /// stated expectations vs. failed. This is raw evidence collection, not a
  /// verdict — it deliberately does not recommend or apply any threshold
  /// change; a human reading it decides whether "High confidence" is
  /// actually earning its label often enough to trust more heavily later.
  String calibrationSummary() {
    final buffer = StringBuffer();
    buffer.writeln('\n=== Confidence Calibration (Part 14) ===');
    final withEvent = results.where((r) => r.event != null).toList();
    if (withEvent.isEmpty) {
      buffer.writeln('(no cases reached the extractor)');
      return buffer.toString();
    }
    for (final level in ConfidenceLevel.values) {
      final atLevel = withEvent
          .where((r) => r.confidenceLevel == level)
          .toList();
      if (atLevel.isEmpty) continue;
      final passedAtLevel = atLevel.where((r) => r.passed).length;
      final rate = (passedAtLevel / atLevel.length * 100).toStringAsFixed(1);
      buffer.writeln(
        '  ${level.name}: ${atLevel.length} case(s), $passedAtLevel passed '
        '($rate% — "when the system says ${level.name}, it was correct '
        '$rate% of the time in this corpus")',
      );
    }
    final reviewCount = withEvent.where((r) => r.needsReview).length;
    buffer.writeln(
      '  needsReview: $reviewCount / ${withEvent.length} '
      '(${(reviewCount / withEvent.length * 100).toStringAsFixed(1)}%) — '
      'the share of cases the pipeline itself flagged for a human, before '
      'any pass/fail grading is even applied',
    );
    return buffer.toString();
  }
}

/// Runs [SmsTestCase]s through the actual production pipeline — never a
/// mocked/simplified stand-in — and grades the result against each case's
/// [ExpectedFinancialClassification]. Deliberately regex-only by default
/// (no [FinancialEventAiProvider] wired in), matching the honest baseline
/// every user gets whenever the AI call is disabled or fails; pass a
/// provider explicitly to evaluate the AI-assisted path once one is
/// available.
class SmsEvaluationHarness {
  const SmsEvaluationHarness({
    this.extractor = const FinancialEventExtractor(),
    this.confidenceEngine = const FinancialEventConfidenceEngine(),
  });

  final FinancialEventExtractor extractor;

  /// Runs exactly like the production pipeline does (see
  /// `sms_inbox_providers.dart`) so [SmsCaseResult.overallConfidence]/
  /// [SmsCaseResult.confidenceLevel] reflect the real scoring, not
  /// [FinancialEvent.overallConfidence]'s neutral unscored placeholder.
  final FinancialEventConfidenceEngine confidenceEngine;

  static const _defaultAccountMatch = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    matchReason: 'Matched by last-4.',
  );

  Future<SmsCaseResult> evaluate(
    SmsTestCase testCase, {
    AccountMatchResult accountMatch = _defaultAccountMatch,
    AccountCardMatcher? accountCardMatcher,
    List<Category> categories = const [],
    DateTime? fixedDate,
  }) async {
    final expected = testCase.expected;
    final mismatches = <String>[];

    final message = RawSmsMessage(
      address: testCase.sender,
      body: testCase.body,
      date: fixedDate ?? DateTime(2026, 7, 15, 10),
    );
    final passedFilter = SmsFinancialFilter.isFinancial(message);

    if (expected.shouldPassFilter != null &&
        passedFilter != expected.shouldPassFilter) {
      mismatches.add(
        'shouldPassFilter: expected ${expected.shouldPassFilter} but got $passedFilter',
      );
    }

    // A case that expects outright filter-rejection is graded on that alone —
    // it must never reach the parser or the extractor at all.
    if (expected.shouldPassFilter == false) {
      return SmsCaseResult(
        testCase: testCase,
        mismatches: mismatches,
        event: null,
      );
    }

    final parsed = passedFilter
        ? const SmsParserRegistry().tryParse(message)
        : null;

    if (expected.shouldParse != null &&
        (parsed != null) != expected.shouldParse) {
      mismatches.add(
        'shouldParse: expected ${expected.shouldParse} but got ${parsed != null}',
      );
    }

    if (parsed == null) {
      return SmsCaseResult(
        testCase: testCase,
        mismatches: mismatches,
        event: null,
      );
    }

    final item = SmsInboxItem(
      id: 'sms-${testCase.id}',
      messageKey: 'key-${testCase.id}',
      rawMessage: message,
      dedupKey: 'dedup-${testCase.id}',
      status: SmsImportStatus.pending,
      createdAt: message.date,
      parsed: parsed,
    );

    final event = await extractor.extract(
      item: item,
      accountMatch: accountMatch,
      categories: categories,
      accountCardMatcher: accountCardMatcher,
    );
    final scored = confidenceEngine.score(event);

    void check<T>(String field, T? expectedValue, T actualValue) {
      if (expectedValue != null && expectedValue != actualValue) {
        mismatches.add('$field: expected $expectedValue but got $actualValue');
      }
    }

    check('moneyMovement', expected.moneyMovement, event.moneyMovement.value);
    check('direction', expected.direction, event.direction);
    check('eventType', expected.eventType, event.eventType);
    check(
      'transactionStatus',
      expected.transactionStatus,
      event.transactionStatus.value,
    );
    check('paymentMethod', expected.paymentMethod, event.paymentMethod.value);
    check(
      'isOwnAccountTransfer',
      expected.isOwnAccountTransfer,
      event.isOwnAccountTransfer,
    );
    check('role', expected.role, event.role);
    check('merchantType', expected.merchantType, event.merchantType.value);
    check(
      'paymentProvider',
      expected.paymentProvider,
      event.paymentProvider.value,
    );

    if (expected.merchantTypeIsNull == true &&
        event.merchantType.value != null) {
      mismatches.add(
        'merchantType: expected unresolved (never invented) but got '
        '"${event.merchantType.value}"',
      );
    }
    if (expected.paymentProviderIsNull == true &&
        event.paymentProvider.value != null) {
      mismatches.add(
        'paymentProvider: expected unresolved but got '
        '"${event.paymentProvider.value}"',
      );
    }
    if (expected.categoryIsNull == true && event.category.value != null) {
      mismatches.add(
        'category: expected unresolved but got categoryId '
        '"${event.category.value}"',
      );
    }
    if (expected.categoryNameEquals != null) {
      final categoryId = event.category.value;
      String? actualName;
      if (categoryId != null) {
        for (final c in categories) {
          if (c.id == categoryId) {
            actualName = c.name;
            break;
          }
        }
      }
      if (actualName != expected.categoryNameEquals) {
        mismatches.add(
          'category: expected "${expected.categoryNameEquals}" but got '
          '${actualName == null ? "null (categoryId=$categoryId)" : '"$actualName"'}',
        );
      }
    }

    if (expected.amount != null) {
      final actual = event.amount.value;
      if (actual == null || (actual - expected.amount!).abs() > 0.01) {
        mismatches.add('amount: expected ${expected.amount} but got $actual');
      }
    }

    if (expected.merchantEquals != null &&
        event.merchant.value != expected.merchantEquals) {
      mismatches.add(
        'merchant: expected exactly "${expected.merchantEquals}" but got "${event.merchant.value}"',
      );
    }
    if (expected.merchantContains != null) {
      final actual = event.merchant.value ?? '';
      if (!actual.toLowerCase().contains(
        expected.merchantContains!.toLowerCase(),
      )) {
        mismatches.add(
          'merchant: expected to contain "${expected.merchantContains}" but got "$actual"',
        );
      }
    }
    if (expected.merchantIsNull == true && event.merchant.value != null) {
      mismatches.add(
        'merchant: expected null (never invented) but got "${event.merchant.value}"',
      );
    }
    if (expected.referenceNumberIsNull == true &&
        event.referenceNumber != null) {
      mismatches.add(
        'referenceNumber: expected null but got "${event.referenceNumber}"',
      );
    }

    return SmsCaseResult(
      testCase: testCase,
      mismatches: mismatches,
      event: event,
      overallConfidence: scored.overall,
      confidenceLevel: scored.level,
    );
  }

  Future<SmsEvaluationReport> evaluateAll(
    List<SmsTestCase> cases, {
    AccountMatchResult accountMatch = _defaultAccountMatch,
    AccountCardMatcher? accountCardMatcher,
    List<Category> categories = const [],
  }) async {
    final results = <SmsCaseResult>[];
    for (final testCase in cases) {
      results.add(
        await evaluate(
          testCase,
          accountMatch: accountMatch,
          accountCardMatcher: accountCardMatcher,
          categories: categories,
        ),
      );
    }
    return SmsEvaluationReport(results);
  }
}
