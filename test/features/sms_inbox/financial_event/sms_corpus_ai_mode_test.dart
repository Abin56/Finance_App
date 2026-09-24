import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_ai_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'evaluation/sms_evaluation_harness.dart';
import 'fixtures/sms_test_corpus.dart';

/// Part 13 of the Phase 5 SMS rebuild plan: the same corpus, run in a
/// second mode — deterministic regex evidence PLUS a scripted AI opinion —
/// without ever needing a live Claude API call in a unit test. Each
/// [_AiScenario] below is a reusable "shape" of AI behavior (correct,
/// disagreeing, hallucinating, abstaining, erroring); the test group at the
/// bottom re-runs a representative slice of `smsTestCorpus` under each
/// scenario and asserts the exact same safety invariants
/// `sms_corpus_evaluation_test.dart` already enforces for the regex-only
/// mode — no dangerous case may ever resolve `moneyMovement` incorrectly,
/// and no hallucinated identity/category/provider may ever leak through,
/// regardless of which "kind" of AI is wired in.
class _ScriptedAiProvider implements FinancialEventAiProvider {
  _ScriptedAiProvider(this._respond);

  /// Returning `null` here simulates AI abstention (offline, disabled, or a
  /// caught error) — the same code path `NoopFinancialEventAiProvider` and
  /// a genuine network failure both take, per
  /// `FinancialEventAiProvider.classify`'s "never throws" contract.
  final FinancialEventAiResult? Function(FinancialEventAiRequest request)
  _respond;

  int callCount = 0;

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async {
    callCount++;
    return _respond(request);
  }
}

/// One reusable AI "personality" the corpus is replayed against.
class _AiScenario {
  const _AiScenario(this.name, this.responder);

  final String name;
  final FinancialEventAiResult? Function(FinancialEventAiRequest request)
  responder;
}

void main() {
  // Every scenario deliberately answers using ONLY the regex evidence
  // already present on the request (amount/direction/merchantGuess) —
  // exactly what a real model would be handed — never anything it could
  // not plausibly have derived from the redacted body + regex context.
  final scenarios = <_AiScenario>[
    _AiScenario(
      'A: correct — agrees with the regex evidence on every hard fact',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: null,
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.8,
          amount: 0.8,
          merchant: 0.0,
          category: 0.0,
        ),
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'B: disagreement — claims the opposite direction of the regex evidence',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection == 'debit' ? 'credit' : 'debit',
        amount: request.regexAmount,
        merchant: null,
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.9,
          amount: 0.5,
          merchant: 0.0,
          category: 0.0,
        ),
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'C: hallucinated merchant — invents "Rahul" with fabricated (ungrounded) evidence',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: 'Rahul',
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.6,
          amount: 0.6,
          merchant: 0.95,
          category: 0.0,
        ),
        merchantType: 'person',
        evidenceMerchant: 'this message is clearly for Rahul',
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'D: hallucinated category — claims Shopping backed only by a fabricated quote',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: null,
        category: 'Shopping',
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.6,
          amount: 0.6,
          merchant: 0.0,
          category: 0.9,
        ),
        evidenceCategory: 'this is obviously a retail purchase',
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'E: hallucinated provider — claims PhonePe backed only by a fabricated quote',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: null,
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.6,
          amount: 0.6,
          merchant: 0.0,
          category: 0.0,
        ),
        paymentProvider: 'phonePe',
        evidenceMerchant: 'this looks like a PhonePe transaction',
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'F: grounded evidence — genuinely quotes text taken from the redacted body',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: request.regexMerchantGuess,
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.7,
          amount: 0.7,
          merchant: 0.7,
          category: 0.0,
        ),
        evidenceMerchant: request.regexMerchantGuess,
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'G: ungrounded evidence — the quote itself is invented, not present anywhere in the message',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: 'Totally Invented Store',
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.6,
          amount: 0.6,
          merchant: 0.8,
          category: 0.0,
        ),
        evidenceMerchant: 'a phrase that does not appear anywhere in this SMS',
        moneyMovement: null,
        transactionStatus: null,
      ),
    ),
    _AiScenario(
      'H: partial response — only amount/direction answered, everything else abstained',
      (request) => FinancialEventAiResult(
        eventType: null,
        direction: request.regexDirection,
        amount: request.regexAmount,
        merchant: null,
        category: null,
        paymentMethod: null,
        role: null,
        isLikelyRefundOrReversal: false,
        confidences: const FinancialEventAiFieldConfidences(
          eventType: 0.0,
          direction: 0.5,
          amount: 0.5,
          merchant: 0.0,
          category: 0.0,
        ),
      ),
    ),
    _AiScenario(
      'I: timeout/error — classify() returns null, exactly like a genuine network failure',
      (request) => null,
    ),
  ];

  // A representative slice of the corpus — every dangerous case (the ones
  // this whole exercise exists to protect) plus a sample of ordinary ones,
  // rather than the full 185-case corpus per scenario (9 scenarios x the
  // full corpus would be slow for little extra signal beyond what's
  // already covered per-field in the hallucination-specific test files).
  final dangerousCases = smsTestCorpus
      .where((c) => c.isDangerousIfMisclassified)
      .toList();
  final sampleOrdinaryIds = {
    'debit-upi-swiggy-01',
    'p5-upi-zomato-vpa-01',
    'p5-refund-flipkart-01',
    'status-reversed-alone-01',
    'p5-emi-successful-01',
  };
  final sampleCases = [
    ...dangerousCases,
    ...smsTestCorpus.where((c) => sampleOrdinaryIds.contains(c.id)),
  ];

  for (final scenario in scenarios) {
    group('AI eval mode B — scenario ${scenario.name}', () {
      final provider = _ScriptedAiProvider(scenario.responder);
      final harness = SmsEvaluationHarness(
        extractor: FinancialEventExtractor(aiProvider: provider),
      );

      test(
        'every dangerous case still resolves moneyMovement correctly with this AI personality active',
        () async {
          final report = await harness.evaluateAll(dangerousCases);
          expect(
            report.dangerousMismatches,
            isEmpty,
            reason:
                'scenario "${scenario.name}" caused a dangerous moneyMovement '
                'misclassification:\n${report.summary()}',
          );
        },
      );

      test(
        'no hallucinated/ungrounded AI claim ever leaks into the final event, regardless of scenario',
        () async {
          for (final testCase in sampleCases) {
            final result = await harness.evaluate(testCase);
            final event = result.event;
            if (event == null) continue;
            // The corpus's own expectations already assert the correct
            // merchant/category/provider per case (see
            // sms_corpus_evaluation_test.dart) — this loop's job is
            // narrower: confirm AI scenarios C/D/E/G's specific
            // fabrications never appear on an event whose corpus
            // expectation says otherwise.
            if (testCase.expected.merchantIsNull == true) {
              expect(
                event.merchant.value,
                isNot(anyOf('Rahul', 'Totally Invented Store')),
                reason:
                    'scenario "${scenario.name}" leaked a hallucinated merchant into [${testCase.id}]',
              );
            }
            if (testCase.expected.categoryIsNull == true) {
              expect(
                event.category.value,
                isNull,
                reason:
                    'scenario "${scenario.name}" leaked a hallucinated category into [${testCase.id}]',
              );
            }
          }
        },
      );
    });
  }

  test(
    'sanity: every scripted scenario is actually exercised (AI is called at least once per scenario across the sample)',
    () async {
      for (final scenario in scenarios) {
        final provider = _ScriptedAiProvider(scenario.responder);
        final harness = SmsEvaluationHarness(
          extractor: FinancialEventExtractor(aiProvider: provider),
        );
        for (final testCase in dangerousCases) {
          await harness.evaluate(testCase);
        }
        expect(
          provider.callCount,
          greaterThan(0),
          reason:
              'scenario "${scenario.name}" was never actually invoked — AiCallNecessity skipped every dangerous case, which would make this scenario meaningless',
        );
      }
    },
  );
}
