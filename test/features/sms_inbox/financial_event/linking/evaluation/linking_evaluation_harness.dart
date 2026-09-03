import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_engine.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_repository.dart';

import '../fixtures/linking_test_case.dart';

class LinkingCaseResult {
  const LinkingCaseResult({
    required this.testCase,
    required this.mismatches,
    required this.relationship,
  });

  final LinkingTestCase testCase;
  final List<String> mismatches;
  final EventRelationship relationship;

  bool get isKnownIssue => testCase.knownIssue != null;
  bool get passed => mismatches.isEmpty || isKnownIssue;

  bool get isDangerousMismatch =>
      !isKnownIssue && mismatches.isNotEmpty && testCase.isDangerousIfMisclassified;
}

class LinkingEvaluationReport {
  const LinkingEvaluationReport(this.results);

  final List<LinkingCaseResult> results;

  int get total => results.length;
  int get passedCount => results.where((r) => r.passed).length;
  int get failedCount => total - passedCount;
  List<LinkingCaseResult> get failures => results.where((r) => !r.passed).toList();
  List<LinkingCaseResult> get dangerousMismatches =>
      results.where((r) => r.isDangerousMismatch).toList();
  List<LinkingCaseResult> get knownIssues =>
      results.where((r) => r.isKnownIssue).toList();

  double get passRate => total == 0 ? 1.0 : passedCount / total;

  String summary() {
    final buffer = StringBuffer();
    buffer.writeln('=== Linking Evaluation Report ===');
    buffer.writeln(
      'Total: $total   Passed: $passedCount   Failed: $failedCount   '
      'Pass rate: ${(passRate * 100).toStringAsFixed(1)}%',
    );
    if (dangerousMismatches.isNotEmpty) {
      buffer.writeln(
        '\n!!! ${dangerousMismatches.length} DANGEROUS misclassification(s) — relationship verdict is wrong on a case marked safety-critical !!!',
      );
      for (final r in dangerousMismatches) {
        buffer.writeln('  [${r.testCase.id}]');
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
        buffer.writeln('  [${r.testCase.id}]');
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

/// Runs [LinkingTestCase]s through the real [EventRelationshipEngine] —
/// never a mocked stand-in — seeding a fresh
/// [InMemoryEventRelationshipRepository] with each case's `pool` so cases
/// stay fully isolated from each other.
class LinkingEvaluationHarness {
  const LinkingEvaluationHarness();

  Future<LinkingCaseResult> evaluate(LinkingTestCase testCase) async {
    final repository = InMemoryEventRelationshipRepository();
    for (final event in testCase.pool) {
      repository.addEvent(event);
    }
    final engine = EventRelationshipEngine(repository);
    final relationship = await engine.evaluate(
      candidate: testCase.candidate,
      id: 'rel-${testCase.id}',
    );

    final mismatches = <String>[];
    void check<T>(String field, T? expected, T actual) {
      if (expected != null && expected != actual) {
        mismatches.add('$field: expected $expected but got $actual');
      }
    }

    check('relationshipType', testCase.expectedType, relationship.relationshipType);
    check('confidence', testCase.expectedConfidence, relationship.confidence);
    check('needsReview', testCase.expectedNeedsReview, relationship.needsReview);
    if (testCase.expectedTargetEventId != null) {
      check('targetEventId', testCase.expectedTargetEventId, relationship.targetEventId);
    }
    if (testCase.expectedAlternativeCount != null) {
      check(
        'alternativeCandidates.length',
        testCase.expectedAlternativeCount,
        relationship.alternativeCandidates.length,
      );
    }

    return LinkingCaseResult(
      testCase: testCase,
      mismatches: mismatches,
      relationship: relationship,
    );
  }

  Future<LinkingEvaluationReport> evaluateAll(List<LinkingTestCase> cases) async {
    final results = <LinkingCaseResult>[];
    for (final testCase in cases) {
      results.add(await evaluate(testCase));
    }
    return LinkingEvaluationReport(results);
  }
}
