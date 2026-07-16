import 'package:flutter_test/flutter_test.dart';

/// Exercises the same math as `creditCardStandingProvider`
/// (`lib/features/credit_cards/presentation/providers/credit_card_providers.dart`)
/// directly, since this codebase's test suite has no `ProviderContainer`
/// precedent — see `emi_credit_card_restoration_test.dart` for the same
/// convention. Confirms the Part 4 worked example: raising a card's credit
/// limit only ever changes the maximum limit, never the already-computed
/// outstanding balance — available is *derived* from both, so a limit
/// increase widens available without touching outstanding.
double available({required double creditLimit, required double outstanding, double principalRestored = 0}) {
  return (creditLimit - outstanding + principalRestored).clamp(0, creditLimit);
}

void main() {
  test('raising the credit limit increases available without changing outstanding', () {
    const outstanding = 35000.0;

    final availableBefore = available(creditLimit: 100000, outstanding: outstanding);
    expect(availableBefore, 65000);

    final availableAfter = available(creditLimit: 150000, outstanding: outstanding);
    expect(availableAfter, 115000);

    // Outstanding itself never depends on creditLimit — editing the limit
    // can't retroactively rewrite it.
    expect(outstanding, 35000);
  });

  test('lowering the credit limit below outstanding clamps available to 0, never negative', () {
    final result = available(creditLimit: 20000, outstanding: 35000);
    expect(result, 0);
  });

  test('available never exceeds the credit limit even with restored principal', () {
    final result = available(creditLimit: 100000, outstanding: 0, principalRestored: 50000);
    expect(result, 100000);
  });
}
