// Loan principal disbursements (origination borrowed/lent principal, Borrow/
// Lend More) are real Account movements but not income/spending: they stay in
// the raw Transactions stream and leave the calculable list every Cash Flow /
// Dashboard / Reports / Budget total reads. A down payment and EMI repayment
// keep counting. Parity with the web app's
// lib/models/transaction-classification.test.ts.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_allocation_type.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'calculable list drops principal disbursements and transfers only',
    () async {
      final firestore = FakeFirebaseFirestore();
      final col = firestore
          .collection('users')
          .doc('uid')
          .collection('transactions');
      Transaction txn(
        String id,
        TransactionType type,
        double amount, {
        String? loanId,
        PaymentAllocationType? allocation,
        String? transferId,
      }) => Transaction(
        id: id,
        type: type,
        amount: amount,
        dateTime: DateTime(2026, 1, 15),
        accountId: 'hdfc',
        categoryId: 'c',
        createdAt: DateTime(2026, 1, 15),
        loanId: loanId,
        paymentAllocationType: allocation,
        transferId: transferId,
      );
      final rows = [
        txn('salary', TransactionType.income, 90000),
        txn('groceries', TransactionType.expense, 4000),
        txn('transfer-out', TransactionType.expense, 1000, transferId: 't1'),
        txn(
          'orig_k_txn',
          TransactionType.income,
          50000,
          loanId: 'orig_k_loan',
          allocation: PaymentAllocationType.additionalDisbursement,
        ),
        txn(
          'orig_j_txn',
          TransactionType.expense,
          25000,
          loanId: 'orig_j_loan',
          allocation: PaymentAllocationType.additionalDisbursement,
        ),
        txn(
          'orig_p_txn',
          TransactionType.expense,
          10000,
          loanId: 'orig_p_loan',
        ),
        txn(
          'emi',
          TransactionType.expense,
          4500,
          loanId: 'orig_k_loan',
          allocation: PaymentAllocationType.regularEmi,
        ),
      ];
      for (final t in rows) {
        await col.doc(t.id).set(t.toFirestore());
      }

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUserIdProvider.overrideWithValue('uid'),
        ],
      );
      addTearDown(container.dispose);
      final raw = await container.read(transactionsStreamProvider.future);
      expect(raw, hasLength(rows.length));

      final calculable = container.read(calculableTransactionsProvider);
      expect(calculable.map((t) => t.id).toSet(), {
        'salary',
        'groceries',
        'orig_p_txn',
        'emi',
      });
      final income = calculable
          .where((t) => t.type == TransactionType.income)
          .fold<double>(0, (total, t) => total + t.amount);
      final spending = calculable
          .where((t) => t.type == TransactionType.expense)
          .fold<double>(0, (total, t) => total + t.amount);
      expect(income, 90000);
      expect(spending, 4000 + 10000 + 4500);
    },
  );

  test('allocation alone, without a Loan link, never excludes', () {
    final t = Transaction(
      id: 'x',
      type: TransactionType.income,
      amount: 1,
      dateTime: DateTime(2026),
      accountId: 'a',
      categoryId: 'c',
      createdAt: DateTime(2026),
      paymentAllocationType: PaymentAllocationType.additionalDisbursement,
    );
    expect(t.isLoanPrincipalDisbursement, isFalse);
    expect(t.isNonIncomeExpenseMovement, isFalse);
  });
}
