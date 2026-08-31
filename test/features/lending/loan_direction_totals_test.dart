import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the dashboard's "To Receive"/"To Pay" split
/// (`totalAmountToReceiveProvider`/`totalAmountToPayProvider`) added for
/// dual-direction Loans — both must include only non-closed loans of their
/// own direction, and never a loan of the other direction or a closed one
/// (a loan can be closed early as forgiven/written-off while still carrying
/// an unpaid balance — see `Loan.isClosed` — and that leftover balance must
/// not inflate the dashboard total).
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

  test('totalAmountToReceiveProvider sums only given loans, totalAmountToPayProvider sums only taken loans', () async {
    final repository = container.read(loanRepositoryProvider);
    await repository.createLoan(
      personId: 'p1',
      direction: LoanDirection.given,
      loanAmount: 500,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2, 1),
    );
    await repository.createLoan(
      personId: 'p2',
      direction: LoanDirection.taken,
      loanAmount: 300,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2, 1),
    );

    final loans = await container.read(loansStreamProvider.future);
    for (final loan in loans) {
      await container.read(installmentsStreamProvider(loan.scheduleId).future);
    }

    expect(container.read(totalAmountToReceiveProvider), 500);
    expect(container.read(totalAmountToPayProvider), 300);
  });

  test('a closed loan is excluded from both totals even if it still carries an unpaid balance', () async {
    final repository = container.read(loanRepositoryProvider);
    final given = await repository.createLoan(
      personId: 'p1',
      direction: LoanDirection.given,
      loanAmount: 1000,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2, 1),
    );
    final taken = await repository.createLoan(
      personId: 'p2',
      direction: LoanDirection.taken,
      loanAmount: 800,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 2, 1),
    );
    final createdLoans = await container.read(loansStreamProvider.future);
    for (final loan in createdLoans) {
      await container.read(installmentsStreamProvider(loan.scheduleId).future);
    }

    // Neither loan has had any payment recorded, so closing them (forgiven/
    // written off) leaves a full unpaid balance behind on their schedules.
    await repository.closeLoan(given);
    await repository.closeLoan(taken);
    await container.read(loansStreamProvider.future);

    expect(container.read(totalAmountToReceiveProvider), 0);
    expect(container.read(totalAmountToPayProvider), 0);
  });
}
