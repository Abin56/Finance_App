import 'package:finance_app/features/sms_inbox/domain/financial_event/ai_call_necessity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AiCallNecessityInput input({
    bool hasUnresolvedMerchantText = false,
    bool hasUnresolvedCategory = false,
    bool eventTypeIsAmbiguous = false,
  }) {
    return AiCallNecessityInput(
      hasUnresolvedMerchantText: hasUnresolvedMerchantText,
      hasUnresolvedCategory: hasUnresolvedCategory,
      eventTypeIsAmbiguous: eventTypeIsAmbiguous,
    );
  }

  test('everything resolved and unambiguous -> no AI call needed', () {
    expect(AiCallNecessity.isNecessary(input()), isFalse);
  });

  test(
    'an unresolved merchant (a counterparty was named but not identified) -> AI call needed',
    () {
      expect(
        AiCallNecessity.isNecessary(input(hasUnresolvedMerchantText: true)),
        isTrue,
      );
    },
  );

  test(
    'a message with no merchant at all (e.g. a salary credit) does NOT force an AI call on its own',
    () {
      expect(
        AiCallNecessity.isNecessary(input(hasUnresolvedMerchantText: false)),
        isFalse,
      );
    },
  );

  test('an unresolved category -> AI call needed', () {
    expect(
      AiCallNecessity.isNecessary(input(hasUnresolvedCategory: true)),
      isTrue,
    );
  });

  test(
    'ambiguous event type alone -> AI call needed, even with everything else resolved',
    () {
      expect(
        AiCallNecessity.isNecessary(input(eventTypeIsAmbiguous: true)),
        isTrue,
      );
    },
  );

  test('every signal unresolved -> AI call needed', () {
    expect(
      AiCallNecessity.isNecessary(
        input(
          hasUnresolvedMerchantText: true,
          hasUnresolvedCategory: true,
          eventTypeIsAmbiguous: true,
        ),
      ),
      isTrue,
    );
  });
}
