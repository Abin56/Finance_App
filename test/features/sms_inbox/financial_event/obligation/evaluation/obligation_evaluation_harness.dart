import 'package:finance_app/features/sms_inbox/domain/obligation/financial_obligation.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_builder.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_classifier.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_semantic_bucket.dart';

import '../fixtures/obligation_test_case.dart';

/// The outcome of running one [ObligationTestCase] through the real
/// [ObligationClassifier]/[ObligationBuilder] pair and comparing the result
/// against [ObligationTestCase.expected]. Mirrors `SmsCaseResult`.
class ObligationCaseResult {
  const ObligationCaseResult({
    required this.testCase,
    required this.mismatches,
    required this.classification,
    required this.obligation,
  });

  final ObligationTestCase testCase;
  final List<String> mismatches;
  final ObligationClassificationResult classification;

  /// The built obligation, or `null` when the classifier resolved to a
  /// non-outstanding bucket (exactly the expected outcome for a completed/
  /// pending/failed/reversed/refund/unknown case).
  final FinancialObligation? obligation;

  bool get isKnownIssue => testCase.knownIssue != null;

  bool get passed => mismatches.isEmpty || isKnownIssue;

  /// True only when this case is marked
  /// [ObligationTestCase.isDangerousIfMisclassified] AND it failed.
  bool get isDangerousMismatch =>
      !isKnownIssue &&
      mismatches.isNotEmpty &&
      testCase.isDangerousIfMisclassified;
}

class ObligationEvaluationReport {
  const ObligationEvaluationReport(this.results);

  final List<ObligationCaseResult> results;

  int get total => results.length;
  int get passedCount => results.where((r) => r.passed).length;
  int get failedCount => total - passedCount;
  List<ObligationCaseResult> get failures =>
      results.where((r) => !r.passed).toList();
  List<ObligationCaseResult> get dangerousMismatches =>
      results.where((r) => r.isDangerousMismatch).toList();
  List<ObligationCaseResult> get knownIssues =>
      results.where((r) => r.isKnownIssue).toList();

  double get passRate => total == 0 ? 1.0 : passedCount / total;

  String summary() {
    final buffer = StringBuffer();
    buffer.writeln('=== Obligation Evaluation Report ===');
    buffer.writeln(
      'Total: $total   Passed: $passedCount   Failed: $failedCount   '
      'Pass rate: ${(passRate * 100).toStringAsFixed(1)}%',
    );
    if (dangerousMismatches.isNotEmpty) {
      buffer.writeln(
        '\n!!! ${dangerousMismatches.length} DANGEROUS misclassification(s) — obligation/transaction verdict is wrong on a case marked safety-critical !!!',
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
    return buffer.toString();
  }
}

/// Runs [ObligationTestCase]s through the actual production
/// [ObligationClassifier]/[ObligationBuilder] — never a mocked stand-in —
/// and grades the result. Mirrors `SmsEvaluationHarness`.
class ObligationEvaluationHarness {
  const ObligationEvaluationHarness({
    this.classifier = const ObligationClassifier(),
    this.builder = const ObligationBuilder(),
  });

  final ObligationClassifier classifier;
  final ObligationBuilder builder;

  static final _defaultReceivedAt = DateTime(2026, 9, 1, 10);

  ObligationCaseResult evaluate(ObligationTestCase testCase) {
    final expected = testCase.expected;
    final mismatches = <String>[];
    final receivedAt = testCase.receivedAt ?? _defaultReceivedAt;

    final classification = classifier.classify(
      body: testCase.body,
      transactionStatus: testCase.transactionStatus,
      moneyMovement: testCase.moneyMovement,
      eventType: testCase.eventType,
    );

    void check<T>(String field, T? expectedValue, T actualValue) {
      if (expectedValue != null && expectedValue != actualValue) {
        mismatches.add('$field: expected $expectedValue but got $actualValue');
      }
    }

    check('bucket', expected.bucket, classification.bucket);
    check(
      'obligationType',
      expected.obligationType,
      classification.obligationType,
    );
    check(
      'isOutstanding',
      expected.isOutstanding,
      classification.bucket.isOutstanding,
    );

    final obligation = builder.build(
      id: 'obl-${testCase.id}',
      sourceEventId: 'sms-${testCase.id}',
      body: testCase.body,
      smsReceivedAt: receivedAt,
      transactionStatus: testCase.transactionStatus,
      moneyMovement: testCase.moneyMovement,
      eventType: testCase.eventType,
    );

    if (expected.dueDateIsKnown != null) {
      final actualKnown = obligation?.dueDate.isKnown ?? false;
      if (actualKnown != expected.dueDateIsKnown) {
        mismatches.add(
          'dueDateIsKnown: expected ${expected.dueDateIsKnown} but got $actualKnown',
        );
      }
    }
    if (expected.dueDateEquals != null) {
      final actual = obligation?.dueDate.value;
      final expectedDate = expected.dueDateEquals!;
      final matches =
          actual != null &&
          actual.year == expectedDate.year &&
          actual.month == expectedDate.month &&
          actual.day == expectedDate.day;
      if (!matches) {
        mismatches.add(
          'dueDate: expected ${expectedDate.toIso8601String()} but got ${actual?.toIso8601String()}',
        );
      }
    }
    if (expected.dueDateKind != null) {
      final actualKind = obligation?.dueDate.kind;
      final expectedKindName = expected.dueDateKind!.name;
      if (actualKind?.name != expectedKindName) {
        mismatches.add(
          'dueDateKind: expected $expectedKindName but got ${actualKind?.name}',
        );
      }
    }

    return ObligationCaseResult(
      testCase: testCase,
      mismatches: mismatches,
      classification: classification,
      obligation: obligation,
    );
  }

  ObligationEvaluationReport evaluateAll(List<ObligationTestCase> cases) {
    return ObligationEvaluationReport(
      cases.map(evaluate).toList(growable: false),
    );
  }
}
