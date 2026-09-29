import 'package:finance_app/features/lending/domain/loan_balance_sheet.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Global Loan/EMI liability + Net Worth — same cases as Web's
/// `lib/engines/global-liability.test.ts`. Outstanding principal flows once
/// into the balance sheet, [liabilityTotals] and [netWorthWithLoans] — never
/// the original amount, the schedule total, or this cycle's installment.
/// (Principal after payments/prepayments/reversals is covered by
/// `loan_principal_prepayment_test.dart`.)
LoanPrincipalPosition _borrowed(double p, {bool card = false}) =>
    LoanPrincipalPosition(
      direction: LoanDirection.taken,
      outstandingPrincipal: p,
      ownedByTrackedCard: card,
    );

void main() {
  test('A — a ₹1,00,000 Loan received into an account: debt ₹1,00,000, Net Worth unchanged', () {
    final sheet = LoanBalanceSheet.from(loans: [_borrowed(100000)], emis: const []);
    expect(liabilityTotals(sheet, 0).loanDebt, 100000);
    expect(netWorthWithLoans(100000, sheet), 0);
  });

  test('B — ₹10,000 principal repaid: debt ₹90,000, Net Worth does not drop twice', () {
    final sheet = LoanBalanceSheet.from(loans: [_borrowed(90000)], emis: const []);
    expect(liabilityTotals(sheet, 0).loanDebt, 90000);
    expect(netWorthWithLoans(90000, sheet), 0);
  });

  test('C — ₹5,000 EMI with ₹1,000 interest: Net Worth falls only by the interest', () {
    final sheet = LoanBalanceSheet.from(loans: [_borrowed(96000)], emis: const []);
    expect(netWorthWithLoans(95000, sheet), -1000);
  });

  test('D — multiple Loans sum remaining principal', () {
    final sheet = LoanBalanceSheet.from(
      loans: [_borrowed(50000), _borrowed(20000)],
      emis: const [],
    );
    expect(liabilityTotals(sheet, 0).loanDebt, 70000);
  });

  test('E — a Person Loan is one liability; People direct balance never re-adds it', () {
    final sheet = LoanBalanceSheet.from(loans: [_borrowed(20000)], emis: const []);
    expect(liabilityTotals(sheet, 0).total, 20000);
    expect(netWorthWithLoans(0, sheet, peopleDirectBalance: 0), -20000);
  });

  test('H — fully repaid contributes ₹0', () {
    final sheet = LoanBalanceSheet.from(loans: [_borrowed(0)], emis: const []);
    expect(liabilityTotals(sheet, 0).total, 0);
  });

  test('I — a card-linked EMI counts once, on the card line only', () {
    final sheet = LoanBalanceSheet.from(
      loans: const [],
      emis: const [
        EmiPrincipalPosition(outstandingPrincipal: 15000, ownedByTrackedCard: true),
      ],
      cardLockedEmiPrincipal: 15000,
    );
    final totals = liabilityTotals(sheet, 5000);
    expect(totals.emis, 0);
    expect(totals.creditCards, 20000);
    expect(totals.total, 20000);
  });

  test('a card-funded Loan is the card\'s liability, never also "borrowed"', () {
    final sheet = LoanBalanceSheet.from(
      loans: [_borrowed(40000, card: true)],
      emis: const [],
    );
    expect(liabilityTotals(sheet, 40000).loans, 0);
    expect(liabilityTotals(sheet, 40000).total, 40000);
  });

  test('lent principal is an asset, never a liability', () {
    final sheet = LoanBalanceSheet.from(
      loans: const [
        LoanPrincipalPosition(direction: LoanDirection.given, outstandingPrincipal: 8000),
      ],
      emis: const [],
    );
    expect(liabilityTotals(sheet, 0).total, 0);
    expect(netWorthWithLoans(0, sheet), 8000);
  });

  test('People direct balance: a ₹1,000 card purchase made for someone nets to ₹0', () {
    // SBI 7,000 + card account −1,000; person owes me 1,000 → Net Worth 7,000.
    final sheet = LoanBalanceSheet.from(loans: const [], emis: const []);
    expect(netWorthWithLoans(6000, sheet, peopleDirectBalance: 1000), 7000);
  });

  test('audit scenario: ₹25,000 Loan (not into an account), ₹2,500 paid, ₹1,000 card', () {
    final sheet = LoanBalanceSheet.from(loans: [_borrowed(22500)], emis: const []);
    final totals = liabilityTotals(sheet, 1000);
    expect(totals.loanDebt, 22500);
    expect(totals.total, 23500);
    // SBI 4,500 + card −1,000 − 22,500 + 1,000 owed to me.
    expect(netWorthWithLoans(3500, sheet, peopleDirectBalance: 1000), -18000);
  });
}
