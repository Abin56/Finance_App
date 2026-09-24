// Cross-platform parity: both Finance_App (this file) and flowfi-web
// (tests/cross-platform-fixtures/golden-fixture-parity.test.ts) load the
// SAME JSON fixtures (byte-identical copies in each repo, per this
// codebase's established convention for shared Firestore contracts — see
// FirestoreCollections' doc comment) and assert both platforms parse the
// new Advance/Prepayment schema fields identically. A payment created on
// one platform must be correctly understood by the other; this is the
// direct evidence of that, not just matching field names in source code.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadFixture(String filename) {
  final file = File('test/cross_platform_fixtures/$filename');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  test(
    'InstallmentPayment fixture (principalPrepayment) parses identically to web',
    () async {
      final fixture = _loadFixture('installment_payment_advance_fixture.json');
      final expected = fixture['expected'] as Map<String, dynamic>;

      final raw = {
        'installmentId': fixture['installmentId'],
        'scheduleId': fixture['scheduleId'],
        'ownerType': fixture['ownerType'],
        'ownerId': fixture['ownerId'],
        'amount': fixture['amount'],
        'date': Timestamp.fromMillisecondsSinceEpoch(fixture['dateMillis'] as int),
        'note': fixture['note'],
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(fixture['createdAtMillis'] as int),
        'settlementMethod': fixture['settlementMethod'],
        'billingCycleLabel': fixture['billingCycleLabel'],
        'remainingBalanceAfterPayment': fixture['remainingBalanceAfterPayment'],
        'allocationType': fixture['allocationType'],
        'prepaymentPrincipalAmount': fixture['prepaymentPrincipalAmount'],
        'prepaymentPolicyApplied': fixture['prepaymentPolicyApplied'],
        'reamortizationEventId': fixture['reamortizationEventId'],
        'transactionId': fixture['transactionId'],
        'deletedAt': fixture['deletedAt'],
        'lastEditedAt': fixture['lastEditedAt'],
        'editHistory': fixture['editHistory'],
      };

      await firestore.collection('raw').doc('p1').set(raw);
      final snapshot = await firestore.collection('raw').doc('p1').get();
      final payment = InstallmentPayment.fromFirestore(snapshot, null);

      expect(payment.amount, expected['amount']);
      expect(payment.allocationType, PaymentAllocationType.principalPrepayment);
      expect(payment.prepaymentPrincipalAmount, expected['prepaymentPrincipalAmount']);
      expect(payment.prepaymentPolicyApplied, expected['prepaymentPolicyApplied']);
      expect(payment.reamortizationEventId, expected['reamortizationEventId']);
      expect(payment.transactionId, expected['transactionId']);
    },
  );

  test(
    'Transaction fixture (loan payment, principalPrepayment) parses identically to web',
    () async {
      final fixture = _loadFixture('transaction_loan_payment_fixture.json');
      final expected = fixture['expected'] as Map<String, dynamic>;

      final raw = {
        'type': fixture['type'],
        'amount': fixture['amount'],
        'dateTime': Timestamp.fromMillisecondsSinceEpoch(fixture['dateTimeMillis'] as int),
        'accountId': fixture['accountId'],
        'categoryId': fixture['categoryId'],
        'description': fixture['description'],
        'notes': fixture['notes'],
        'receiptPurpose': fixture['receiptPurpose'],
        'transferId': fixture['transferId'],
        'excludeFromCalculations': fixture['excludeFromCalculations'],
        'accountingMonth': fixture['accountingMonth'],
        'linkedPersonId': fixture['linkedPersonId'],
        'owesPersonToggle': fixture['owesPersonToggle'],
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(fixture['createdAtMillis'] as int),
        'source': fixture['source'],
        'loanId': fixture['loanId'],
        'emiId': fixture['emiId'],
        'installmentId': fixture['installmentId'],
        'installmentPaymentId': fixture['installmentPaymentId'],
        'paymentAllocationType': fixture['paymentAllocationType'],
        'deletedAt': fixture['deletedAt'],
        'lastEditedAt': fixture['lastEditedAt'],
        'editHistory': fixture['editHistory'],
      };

      await firestore.collection('rawTxn').doc('t1').set(raw);
      final snapshot = await firestore.collection('rawTxn').doc('t1').get();
      final transaction = Transaction.fromFirestore(snapshot, null);

      expect(transaction.type, TransactionType.expense);
      expect(transaction.amount, expected['amount']);
      expect(transaction.accountId, expected['accountId']);
      expect(transaction.loanId, expected['loanId']);
      expect(transaction.emiId, expected['emiId']);
      expect(transaction.installmentId, expected['installmentId']);
      expect(transaction.installmentPaymentId, expected['installmentPaymentId']);
      expect(
        transaction.paymentAllocationType,
        PaymentAllocationType.principalPrepayment,
      );
    },
  );
}
