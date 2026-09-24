import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_financial_summary.dart';
import 'package:finance_app/features/lending/domain/loan_interest.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/widgets/loan_interest_breakdown_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Every scenario below seeds `Installment.principalPortion`/`interestPortion`
// with fixed, hand-picked numbers standing in for whatever
// `InterestCalculator` actually produced when the schedule was generated.
// The card must render exactly those numbers back — it must never call
// `InterestCalculator` itself, so these tests never import or reference it.

Installment _installment({
  required int sequenceNumber,
  required double amountDue,
  double? principalPortion,
  double? interestPortion,
}) {
  return Installment(
    id: 'i$sequenceNumber',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: sequenceNumber,
    dueDate: DateTime(2026, sequenceNumber, 1),
    amountDue: amountDue,
    principalPortion: principalPortion,
    interestPortion: interestPortion,
    createdAt: DateTime(2026, 1, 1),
  );
}

Loan _loan({LoanInterest? interest}) {
  return Loan(
    id: 'loan-1',
    loanAmount: 65000,
    loanDate: DateTime(2026, 1, 1),
    repaymentType: LoanRepaymentType.installment,
    scheduleId: 'schedule-1',
    createdAt: DateTime(2026, 1, 1),
    interest: interest,
    installmentFrequency: ScheduleType.monthly,
    installmentCount: 2,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));
}

void main() {
  group('LoanInterestBreakdownCard', () {
    testWidgets('zero interest shows "No interest" instead of an empty section', (tester) async {
      final installments = [
        _installment(sequenceNumber: 1, amountDue: 5000),
        _installment(sequenceNumber: 2, amountDue: 5000),
      ];
      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 10000);
      final loan = _loan();

      await _pump(tester, LoanInterestBreakdownCard(loan: loan, installments: installments, summary: summary));

      expect(find.text('No interest'), findsOneWidget);
      expect(find.text('Total Interest'), findsNothing);
    });

    testWidgets('flat interest shows the explainer and per-installment interest, not an amortization table', (tester) async {
      // Flat interest on 10,000 principal @ fixed rate: 500 interest/period.
      final installments = [
        _installment(sequenceNumber: 1, amountDue: 5500, principalPortion: 5000, interestPortion: 500),
        _installment(sequenceNumber: 2, amountDue: 5500, principalPortion: 5000, interestPortion: 500),
      ];
      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 10000);
      final loan = _loan(interest: const LoanInterest(type: InterestType.flat, ratePercent: 5, period: InterestPeriod.monthly));

      await _pump(tester, LoanInterestBreakdownCard(loan: loan, installments: installments, summary: summary));

      expect(find.text('Interest is calculated on the original principal.'), findsOneWidget);
      expect(find.text('₹10,000.00'), findsOneWidget); // Principal
      expect(find.text('₹1,000.00'), findsOneWidget); // Total Interest = 500*2
      expect(find.text('₹11,000.00'), findsOneWidget); // Total Payable
      expect(find.text('Flat Interest'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('reducing balance shows an amortization table matching installment records exactly', (tester) async {
      // Values below mirror a real InterestCalculator.reducingBalance output
      // for a small example — this test only checks the widget reproduces
      // them verbatim, not that they're mathematically "correct" (that's
      // interest_calculator_test.dart's job).
      final installments = [
        _installment(sequenceNumber: 1, amountDue: 3333, principalPortion: 2209, interestPortion: 1124),
        _installment(sequenceNumber: 2, amountDue: 3333, principalPortion: 2247, interestPortion: 1086),
      ];
      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 4456);
      final loan =
          _loan(interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 1.73, period: InterestPeriod.monthly));

      await _pump(tester, LoanInterestBreakdownCard(loan: loan, installments: installments, summary: summary));

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Reducing Balance'), findsOneWidget);
      expect(find.text('1.73% Per Month'), findsOneWidget);

      // Row 1 principal/interest/balance.
      expect(find.text('₹2,209.00'), findsOneWidget);
      expect(find.text('₹1,124.00'), findsOneWidget);
      // Balance after row 1 = totalPrincipal(4456) - 2209 = 2247.
      expect(find.text('₹2,247.00'), findsWidgets); // appears as both row-2 principal and row-1 balance
      // Balance after row 2 = 0 (fully amortized).
      expect(find.text('₹0.00'), findsOneWidget);
    });

    testWidgets('summary section shows only relevant fields when interest is present', (tester) async {
      final installments = [
        _installment(sequenceNumber: 1, amountDue: 3333, principalPortion: 2209, interestPortion: 1124),
      ];
      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 2209);
      final loan =
          _loan(interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 1.73, period: InterestPeriod.monthly));

      await _pump(tester, LoanInterestBreakdownCard(loan: loan, installments: installments, summary: summary));

      expect(find.text('Principal'), findsWidgets);
      expect(find.text('Total Interest'), findsOneWidget);
      expect(find.text('Total Payable'), findsOneWidget);
      expect(find.text('Rate'), findsOneWidget);
      expect(find.text('Method'), findsOneWidget);
    });
  });
}
