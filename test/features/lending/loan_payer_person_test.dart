import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for `Loan.payerPersonId` — "I took a bank loan, but a
/// friend pays the EMIs" (Case 1 of the 3-case Loans hardening request).
/// `loansPayableByPersonProvider` must find loans by [payerPersonId], distinct
/// from `loansForPersonProvider` (which finds loans by `personId`, the
/// lender/counterparty) — a person can be linked to a loan either way, or
/// both, and the two providers must never conflate them.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  test('loansPayableByPersonProvider finds a loan by payerPersonId, not personId', () async {
    final repository = container.read(loanRepositoryProvider);
    await repository.createLoan(
      category: LoanCategory.institutional,
      institutionName: 'HDFC Bank',
      payerPersonId: 'friend-1',
      loanAmount: 50000,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2, 1),
    );
    await container.read(loansStreamProvider.future);

    final payable = container.read(loansPayableByPersonProvider('friend-1'));
    expect(payable, hasLength(1));
    expect(payable.single.institutionName, 'HDFC Bank');

    // This person is only the payer, never the lender/counterparty.
    expect(container.read(loansForPersonProvider('friend-1')), isEmpty);
  });

  test('loansForPersonProvider and loansPayableByPersonProvider stay independent for a personal loan with no payer link', () async {
    final repository = container.read(loanRepositoryProvider);
    await repository.createLoan(
      category: LoanCategory.personal,
      personId: 'friend-2',
      loanAmount: 1000,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2, 1),
    );
    await container.read(loansStreamProvider.future);

    expect(container.read(loansForPersonProvider('friend-2')), hasLength(1));
    expect(container.read(loansPayableByPersonProvider('friend-2')), isEmpty);
  });

  test('loanNextUpcomingInstallmentProvider returns the earliest unpaid installment', () async {
    final repository = container.read(loanRepositoryProvider);
    final loan = await repository.createLoan(
      category: LoanCategory.institutional,
      institutionName: 'HDFC Bank',
      payerPersonId: 'friend-1',
      loanAmount: 300,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.installment,
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 3,
    );
    final installments = await container.read(installmentsStreamProvider(loan.scheduleId).future);
    expect(installments, hasLength(3));

    final next = container.read(loanNextUpcomingInstallmentProvider(loan));
    expect(next, isNotNull);
    expect(next!.sequenceNumber, 1);
  });
}
