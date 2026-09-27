// Cross-platform parity for the Phase 1-2 derived Loan figures: Finance_App
// (this file) and flowfi-web (tests/cross-platform-fixtures/
// golden-fixture-parity.test.ts, "derived Loan figures") load the SAME
// byte-identical JSON fixture, parse its raw InstallmentPayment documents
// with their own fromFirestore, and must compute identical prepaid total,
// outstanding principal, count-once flags and Net Worth.
import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/loan_cash_flow.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/lending/domain/loan_balance_sheet.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_principal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derived Loan figures match flowfi-web for the shared fixture', () async {
    final fixture =
        jsonDecode(File('test/cross_platform_fixtures/loan_derived_figures_fixture.json').readAsStringSync())
            as Map<String, dynamic>;
    final expected = fixture['expected'] as Map<String, dynamic>;
    final firestore = FakeFirebaseFirestore();

    final payments = <InstallmentPayment>[];
    for (final raw in (fixture['payments'] as List).cast<Map<String, dynamic>>()) {
      final ref = firestore.collection('raw').doc(raw['id'] as String);
      await ref.set({
        'installmentId': raw['installmentId'],
        'scheduleId': 's1',
        'ownerType': 'loan',
        'ownerId': 'loan1',
        'amount': raw['amount'],
        'date': Timestamp.fromMillisecondsSinceEpoch(1767225600000),
        'note': '',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1767225600000),
        'allocationType': raw['allocationType'],
        'prepaymentPrincipalAmount': raw['prepaymentPrincipalAmount'],
        'transactionId': raw['transactionId'],
        'deletedAt': (raw['deleted'] as bool) ? Timestamp.fromMillisecondsSinceEpoch(1767312000000) : null,
        'editHistory': const [],
      });
      payments.add(InstallmentPayment.fromFirestore(await ref.get(), null));
    }

    var seq = 0;
    final installments = [
      for (final raw in (fixture['installments'] as List).cast<Map<String, dynamic>>())
        Installment(
          id: 'i${++seq}',
          scheduleId: 's1',
          ownerType: OwnerType.loan,
          ownerId: 'loan1',
          sequenceNumber: seq,
          dueDate: DateTime(2026, seq),
          amountDue: (raw['amountDue'] as num).toDouble(),
          amountPaid: (raw['amountPaid'] as num).toDouble(),
          isSkipped: raw['isSkipped'] as bool,
          principalPortion: (raw['principalPortion'] as num?)?.toDouble(),
          createdAt: DateTime(2026),
        ),
    ];

    final prepaid = principalPrepaidFor(payments);
    final outstanding = outstandingPrincipalAfterPrepayments(
      loanAmount: (fixture['loanAmount'] as num).toDouble(),
      installments: installments,
      principalPrepaid: prepaid,
    );
    final sheet = LoanBalanceSheet.from(
      loans: [
        LoanPrincipalPosition(direction: LoanDirection.taken, outstandingPrincipal: outstanding),
        for (final l in (fixture['otherLoans'] as List).cast<Map<String, dynamic>>())
          LoanPrincipalPosition(
            direction: l['direction'] == 'given' ? LoanDirection.given : LoanDirection.taken,
            outstandingPrincipal: (l['outstandingPrincipal'] as num).toDouble(),
          ),
      ],
      emis: [
        for (final e in (fixture['emis'] as List).cast<Map<String, dynamic>>())
          EmiPrincipalPosition(
            outstandingPrincipal: (e['outstandingPrincipal'] as num).toDouble(),
            ownedByTrackedCard: e['ownedByTrackedCard'] as bool,
          ),
      ],
    );

    expect(prepaid, expected['principalPrepaid']);
    expect(outstanding, expected['outstandingPrincipal']);
    expect(payments.map(countsFromSchedule).toList(), expected['countsFromSchedule']);
    expect(sheet.borrowedPrincipal, expected['borrowedPrincipal']);
    expect(sheet.lentPrincipal, expected['lentPrincipal']);
    expect(sheet.emiPrincipal, expected['emiPrincipal']);
    expect(sheet.cardOwnedEmiPrincipal, expected['cardOwnedEmiPrincipal']);
    expect(netWorthWithLoans((fixture['accountBalances'] as num).toDouble(), sheet), expected['netWorth']);
  });
}
