// Cross-platform parity for card-funded Loan liability ownership. flowfi-web
// runs the same byte-identical fixture through its engines
// (tests/cross-platform-fixtures/card-funded-loan-parity.test.ts); here every
// case is built through Finance_App's REAL repositories and read back from
// its REAL Riverpod providers (creditCardStandingProvider,
// lockedEmiPrincipalForCardProvider, creditUtilizationPercentProvider,
// loanBalanceSheetProvider, netWorthWithLoansProvider).
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/domain/card_emi_ownership.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/reports/presentation/providers/monthly_financial_report_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/cross_platform_fixtures/card_funded_loan_fixture.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final fixture = _fixture();

  test('Web Loan/EMI docs → Flutter → Web: beneficiaryPersonId survives a Flutter whole-document write', () async {
    final firestore = FakeFirebaseFirestore();
    final raw = Map<String, dynamic>.from(fixture['rawLoanDocWithBeneficiary'] as Map)
      ..['loanDate'] = Timestamp.fromMillisecondsSinceEpoch(1767225600000)
      ..['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(1767225600000);
    await firestore.collection('raw').doc('loan-1').set(raw);
    final loan = Loan.fromFirestore(await firestore.collection('raw').doc('loan-1').get(), null);
    expect(cardFundedLoanCardId(loan), 'card-1');
    expect(loan.beneficiaryPersonId, 'person-anu');
    // Flutter's repositories write the whole document (`set`) on every edit /
    // close / trash — the Web association must be written back unchanged.
    loan.isClosed = true;
    await firestore.collection('raw').doc('loan-1').set(loan.toFirestore());
    final reread = (await firestore.collection('raw').doc('loan-1').get()).data()!;
    expect(reread['beneficiaryPersonId'], 'person-anu');

    final emiDoc = <String, dynamic>{
      'name': 'Phone EMI',
      'principalAmount': 40000,
      'startDate': Timestamp.fromMillisecondsSinceEpoch(1767225600000),
      'endDate': Timestamp.fromMillisecondsSinceEpoch(1796083200000),
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1767225600000),
      'installmentFrequency': 'monthly',
      'installmentCount': 8,
      'scheduleId': 'sched-2',
      'beneficiaryPersonId': 'person-anu',
    };
    await firestore.collection('raw').doc('emi-1').set(emiDoc);
    final emi = Emi.fromFirestore(await firestore.collection('raw').doc('emi-1').get(), null);
    expect(emi.beneficiaryPersonId, 'person-anu');
    expect(emi.toFirestore()['beneficiaryPersonId'], 'person-anu');
  });

  test('a lent Loan or a non-card borrowed Loan is never card-owned', () {
    Loan loan({required LoanDirection direction, LoanFundingSource? funding}) => Loan(
      id: 'l',
      loanAmount: 40000,
      loanDate: DateTime(2026, 9, 1),
      repaymentType: LoanRepaymentType.installment,
      scheduleId: 's',
      createdAt: DateTime(2026, 9, 1),
      direction: direction,
      fundingSource: funding,
      linkedCreditCardId: 'card-1',
    );
    expect(cardFundedLoanCardId(loan(direction: LoanDirection.taken, funding: LoanFundingSource.creditCard)), 'card-1');
    expect(cardFundedLoanCardId(loan(direction: LoanDirection.given, funding: LoanFundingSource.creditCard)), isNull);
    expect(cardFundedLoanCardId(loan(direction: LoanDirection.taken, funding: LoanFundingSource.bank)), isNull);
  });

  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () async {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      final now = DateTime.now();

      final accounts = container.read(accountRepositoryProvider);
      await accounts.createAccount(
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: (fixture['bankBalance'] as num).toDouble(),
        colorValue: 0xFF000000,
      );
      final cardAccount = await accounts.createAccount(
        name: 'HDFC',
        type: AccountType.card,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final card = await container.read(creditCardRepositoryProvider).createCard(
            accountId: cardAccount.id,
            statementDay: 5,
            paymentDueDay: 25,
            creditLimit: (fixture['creditLimit'] as num).toDouble(),
          );

      String? purchaseId;
      final purchase = c['purchase'] as Map<String, dynamic>?;
      if (purchase != null) {
        final transactions = container.read(transactionRepositoryProvider);
        final txn = await transactions.createTransaction(
          type: TransactionType.expense,
          amount: (purchase['amount'] as num).toDouble(),
          dateTime: now,
          accountId: cardAccount.id,
          categoryId: 'shopping',
          description: 'Phone',
        );
        purchaseId = txn.id;
        if (purchase['deleted'] as bool) await transactions.softDeleteTransaction(txn);
      }

      final principal = (fixture['principal'] as num).toDouble();
      final loans = container.read(loanRepositoryProvider);
      final loan = await loans.createLoan(
        loanAmount: principal,
        loanDate: now,
        repaymentType: LoanRepaymentType.installment,
        direction: LoanDirection.taken,
        category: LoanCategory.institutional,
        institutionName: 'HDFC Card',
        name: 'Phone',
        installmentFrequency: ScheduleType.monthly,
        installmentCount: (fixture['installmentCount'] as num).toInt(),
        agreementKind: LoanAgreementKind.installmentPurchase,
        fundingSource: LoanFundingSource.creditCard,
        linkedCreditCardId: card.id,
        purchaseTransactionId: purchaseId,
        purchaseAmount: principal,
        downPayment: 0,
      );

      final installments = [
        ...await container.read(installmentsStreamProvider(loan.scheduleId).future),
      ]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      for (final installment in installments.take((c['paidInstallments'] as num).toInt())) {
        final key = (scheduleId: loan.scheduleId, installmentId: installment.id);
        await container
            .read(installmentPaymentRepositoryProvider(key))
            .recordPayment(installment, amount: installment.amountDue, date: now);
      }
      if (c['closed'] as bool) await loans.closeLoan(loan);

      final subs = [
        container.listen(creditCardStandingProvider(card.id), (_, _) {}),
        container.listen(lockedEmiPrincipalForCardProvider(card.id), (_, _) {}),
        container.listen(creditUtilizationPercentProvider, (_, _) {}),
        container.listen(loanBalanceSheetProvider, (_, _) {}),
        container.listen(netWorthWithLoansProvider, (_, _) {}),
        container.listen(loansStreamProvider, (_, _) {}),
      ];
      addTearDown(() {
        for (final s in subs) {
          s.close();
        }
      });
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final expected = c['expected'] as Map<String, dynamic>;
      final standing = container.read(creditCardStandingProvider(card.id));
      final locked = container.read(lockedEmiPrincipalForCardProvider(card.id));
      expect(standing.outstanding, expected['outstanding']);
      expect(locked, expected['lockedEmiPrincipal']);
      expect(standing.available, expected['available']);
      expect(
        container.read(creditUtilizationPercentProvider),
        closeTo((expected['utilizationPercent'] as num).toDouble(), 1e-6),
      );
      expect(container.read(loanBalanceSheetProvider).borrowedPrincipal, expected['borrowedPrincipal']);
      expect(container.read(netWorthWithLoansProvider), expected['netWorth']);
    });
  }
}
