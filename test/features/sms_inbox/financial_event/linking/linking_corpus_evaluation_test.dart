import 'package:flutter_test/flutter_test.dart';

import 'evaluation/linking_evaluation_harness.dart';
import 'fixtures/linking_test_corpus.dart';

void main() {
  test('linking corpus evaluation', () async {
    const harness = LinkingEvaluationHarness();
    final report = await harness.evaluateAll(linkingTestCorpus);

    // ignore: avoid_print
    print(report.summary());

    expect(
      report.dangerousMismatches,
      isEmpty,
      reason:
          'Zero dangerous relationship misclassifications is a hard requirement — see report above.',
    );
    expect(
      report.passRate,
      greaterThanOrEqualTo(0.95),
      reason: 'Ordinary (non-dangerous) mismatches should stay rare — see report above.',
    );
  });
}
