import 'package:flutter_test/flutter_test.dart';

import 'evaluation/obligation_evaluation_harness.dart';
import 'fixtures/obligation_test_corpus.dart';

void main() {
  test('obligation corpus evaluation', () {
    const harness = ObligationEvaluationHarness();
    final report = harness.evaluateAll(obligationTestCorpus);

    // ignore: avoid_print
    print(report.summary());

    expect(
      report.dangerousMismatches,
      isEmpty,
      reason:
          'Zero dangerous reminder <-> completed-transaction misclassifications is a hard requirement — see report above.',
    );
    expect(
      report.passRate,
      greaterThanOrEqualTo(0.95),
      reason:
          'Ordinary (non-dangerous) mismatches should stay rare — see report above.',
    );
  });
}
