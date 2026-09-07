import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/models/payer_source.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/services/payment_attribution_service.dart';
import 'package:finance_app/core/services/providers/payment_attribution_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 9 — Person + Loan + Ledger integration. `personLoanLedgerSummaryProvider`
/// must never recompute a loan or ledger balance of its own; it only adds
/// `Person.currentBalance` to `loanRemainingAmountProvider` sums, which are
/// independent sources (Loans never write a `LedgerEntry` except via
/// `PaymentAttributionService` when a Person other than the account owner
/// pays — that path is tested explicitly below to confirm it produces
/// exactly one ledger effect, not a second UI-level interpretation).
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

  Future<String> createPerson(String name, {double openingBalance = 0}) async {
    final people = container.read(personRepositoryProvider);
    final person = await people.createPerson(name: name, avatarColorValue: 0xFF000000, openingBalance: openingBalance);
    await container.read(peopleStreamProvider.future);
    return person.id;
  }

  Future<({String loanId, String scheduleId, String installmentId})> createLoan({
    required String personId,
    required LoanDirection direction,
    required double amount,
  }) async {
    final loans = container.read(loanRepositoryProvider);
    final loan = await loans.createLoan(
      personId: personId,
      direction: direction,
      loanAmount: amount,
      loanDate: DateTime(2026, 9, 1),
      repaymentType: LoanRepaymentType.oneTime,
      dueDate: DateTime(2026, 9, 5),
    );
    await container.read(loansStreamProvider.future);
    final sub = container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
    addTearDown(sub.close);
    await container.read(installmentsStreamProvider(loan.scheduleId).future);
    final installment = container.read(installmentsStreamProvider(loan.scheduleId)).value!.single;
    return (loanId: loan.id, scheduleId: loan.scheduleId, installmentId: installment.id);
  }

  Future<void> pay(String scheduleId, String installmentId, double amount) async {
    final key = (scheduleId: scheduleId, installmentId: installmentId);
    final sub = container.listen(installmentPaymentsStreamProvider(key), (_, _) {});
    addTearDown(sub.close);
    final installment = container.read(installmentsStreamProvider(scheduleId)).value!.firstWhere((i) => i.id == installmentId);
    await container.read(installmentPaymentRepositoryProvider(key)).recordPayment(installment, amount: amount, date: DateTime(2026, 9, 5));
    await container.read(installmentsStreamProvider(scheduleId).future);
    await container.read(installmentPaymentsStreamProvider(key).future);
  }

  group('PersonLoanLedgerSummary — combined net position', () {
    test('a given loan with no ledger activity: they owe you the outstanding amount', () async {
      final personId = await createPerson('Rahul');
      final loan = await createLoan(personId: personId, direction: LoanDirection.given, amount: 50000);
      await pay(loan.scheduleId, loan.installmentId, 20000);

      final summary = container.read(personLoanLedgerSummaryProvider(personId));
      expect(summary.loanGivenTotal, 50000);
      expect(summary.loanGivenOutstanding, 30000);
      expect(summary.theyOweYou, 30000);
      expect(summary.youOweThem, 0);
      expect(summary.net, 30000);
      expect(summary.isNetReceivable, isTrue);
    });

    test('a taken loan with no ledger activity: you owe them the outstanding amount', () async {
      final personId = await createPerson('Rahul');
      final loan = await createLoan(personId: personId, direction: LoanDirection.taken, amount: 50000);
      await pay(loan.scheduleId, loan.installmentId, 20000);

      final summary = container.read(personLoanLedgerSummaryProvider(personId));
      expect(summary.loanTakenTotal, 50000);
      expect(summary.loanTakenOutstanding, 30000);
      expect(summary.youOweThem, 30000);
      expect(summary.theyOweYou, 0);
      expect(summary.net, -30000);
      expect(summary.isNetReceivable, isFalse);
    });

    test('example from the task: ledger says they owe 30000, loan says you owe 15000 -> net 15000 receivable', () async {
      final personId = await createPerson('Rahul', openingBalance: 30000);
      await createLoan(personId: personId, direction: LoanDirection.taken, amount: 15000);
      // No payment yet — full 15000 still owed by you.

      final summary = container.read(personLoanLedgerSummaryProvider(personId));
      expect(summary.theyOweYou, 30000); // from the ledger (opening balance)
      expect(summary.youOweThem, 15000); // from the loan
      expect(summary.net, 15000);
      expect(summary.isNetReceivable, isTrue);
    });

    test('a closed loan is excluded from the outstanding/total figures', () async {
      final personId = await createPerson('Rahul');
      final closedLoan = await createLoan(personId: personId, direction: LoanDirection.given, amount: 1000);
      await pay(closedLoan.scheduleId, closedLoan.installmentId, 1000); // fully paid, but stays open until closed explicitly

      // Closing is always an explicit user action (`LoanRepository.closeLoan`),
      // never automatic on full payment — mirrors `isClosed`'s doc comment.
      final loans = container.read(loanRepositoryProvider);
      final loan = container.read(loansStreamProvider).value!.firstWhere((l) => l.id == closedLoan.loanId);
      await loans.closeLoan(loan);
      await container.read(loansStreamProvider.future);

      final summary = container.read(personLoanLedgerSummaryProvider(personId));
      expect(summary.loanGivenTotal, 0);
      expect(summary.loanGivenOutstanding, 0);
      expect(summary.theyOweYou, 0);
    });

    test('both given and taken loans for the same person contribute independently, never netted before totals', () async {
      final personId = await createPerson('Rahul');
      final given = await createLoan(personId: personId, direction: LoanDirection.given, amount: 50000);
      final taken = await createLoan(personId: personId, direction: LoanDirection.taken, amount: 20000);
      await pay(given.scheduleId, given.installmentId, 20000);
      await pay(taken.scheduleId, taken.installmentId, 5000);

      final summary = container.read(personLoanLedgerSummaryProvider(personId));
      expect(summary.loanGivenTotal, 50000);
      expect(summary.loanGivenOutstanding, 30000);
      expect(summary.loanTakenTotal, 20000);
      expect(summary.loanTakenOutstanding, 15000);
      expect(summary.theyOweYou, 30000);
      expect(summary.youOweThem, 15000);
      expect(summary.net, 15000);
    });
  });

  group('Payer attribution — no duplicate ledger interpretation', () {
    test('when Rahul pays an EMI for a loan you owe, PaymentAttributionService posts exactly one ledger entry, reflected once in the summary', () async {
      final personId = await createPerson('Rahul');
      final loan = await createLoan(personId: personId, direction: LoanDirection.taken, amount: 50000);

      final installments = container.read(installmentsStreamProvider(loan.scheduleId)).value!;
      final installment = installments.single;
      final person = container.read(peopleStreamProvider).value!.single;

      final ledgerSub = container.listen(ledgerStreamProvider(personId), (_, _) {});
      addTearDown(ledgerSub.close);

      // Rahul (a PersonPayerSource, not the account owner) pays the EMI —
      // this is the ONLY path that ever posts a LedgerEntry for a loan
      // event; installment_payment_repository.dart itself never touches
      // the ledger.
      await container.read(paymentAttributionServiceProvider).apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your loan installment',
            amount: 5000,
            record: ({required amount, required date, required note}) => container
                .read(installmentPaymentRepositoryProvider((scheduleId: loan.scheduleId, installmentId: installment.id)))
                .recordPayment(installment, amount: amount, date: date, note: note, payerPersonId: person.id),
          ),
        ],
        payer: PayerSource.person(person),
        date: DateTime(2026, 9, 5),
      );

      await container.read(installmentsStreamProvider(loan.scheduleId).future);
      await container.read(ledgerStreamProvider(personId).future);
      await container.read(peopleStreamProvider.future);

      // Exactly one ledger entry was posted, of type `borrowed` (they paid,
      // so you now owe them) — never a second, UI-invented interpretation.
      final ledgerEntries = container.read(ledgerStreamProvider(personId)).value!;
      expect(ledgerEntries.length, 1);
      expect(ledgerEntries.single.type, LedgerEntryType.borrowed);
      expect(ledgerEntries.single.amount, 5000);

      // The combined summary reflects this exactly once: the loan
      // installment payment reduced loanTakenOutstanding by 5000, AND the
      // ledger entry independently pushed youOweThem up by 5000 (since
      // `borrowed` means "they paid for me, I owe them more") — these are
      // two genuinely different obligations (the EMI still owed to the
      // bank/lender vs. now owing Rahul back for fronting the cash), not a
      // double count of the same one.
      final summary = container.read(personLoanLedgerSummaryProvider(personId));
      expect(summary.loanTakenOutstanding, 45000); // 50000 - 5000
      expect(summary.ledgerBalance, -5000); // borrowed => -amount
      expect(summary.youOweThem, 45000 + 5000);
    });
  });
}
