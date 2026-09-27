// People ↔ Loans on Flutter, through the REAL repositories and providers
// (fake Firestore). Same scenarios as flowfi-web's emulator suite
// (tests/integration/people-loan-position.test.ts): reproductions of the
// pre-change double count / missing total, then the canonical rule, live
// updates, settlement, and the statement summary card.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/domain/person_loan_ledger_summary.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/people/presentation/providers/person_position_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'uid';
final _date = DateTime(2026, 1, 10);

void main() {
  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUserIdProvider.overrideWithValue(_uid),
      ],
    );
  });
  tearDown(() => container.dispose());

  /// Lets every fake-Firestore stream deliver and every provider recompute.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  Future<Person> person(String name) async {
    final p = await container
        .read(personRepositoryProvider)
        .createPerson(name: name, avatarColorValue: 0, openingBalance: 0);
    // Keep the live chains subscribed, as a mounted People screen would.
    container.listen(personPositionProvider(p.id), (_, _) {});
    container.listen(creditorsProvider, (_, _) {});
    container.listen(debtorsProvider, (_, _) {});
    container.listen(totalReceivableProvider, (_, _) {});
    container.listen(totalPayableProvider, (_, _) {});
    container.listen(personLoanLedgerSummaryProvider(p.id), (_, _) {});
    await settle();
    return p;
  }

  Future<Person> fresh(Person p) async =>
      (await container.read(personRepositoryProvider).getByKey(p.id))!;

  Future<Loan> wizardLoan(
    Person p,
    LoanDirection direction,
    String key, {
    String? accountId,
    double amount = 10000,
  }) async {
    final loan =
        (await container
                .read(loanRepositoryProvider)
                .createAgreementWithOrigination(
                  idempotencyKey: key,
                  name: p.name,
                  category: LoanCategory.personal,
                  personId: p.id,
                  fundingSource: LoanFundingSource.person,
                  direction: direction,
                  loanAmount: amount,
                  loanDate: _date,
                  repaymentType: LoanRepaymentType.installment,
                  installmentFrequency: ScheduleType.monthly,
                  installmentCount: 5,
                  movementAccountId: accountId,
                ))
            .loan;
    container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
    await settle();
    return loan;
  }

  /// The old web Loan form: a Loan plus a Loan-generated ledger entry stamped
  /// `transactionRef = loan.id` (exactly what `postLoanCreatedLedgerEntry`
  /// wrote).
  Future<Loan> oldWebLoan(Person p, LoanDirection direction) async {
    final loan = await container
        .read(loanRepositoryProvider)
        .createLoan(
          loanAmount: 10000,
          loanDate: _date,
          repaymentType: LoanRepaymentType.installment,
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 5,
          personId: p.id,
          direction: direction,
          category: LoanCategory.personal,
          name: 'Rahul loan',
        );
    await container
        .read(ledgerRepositoryProvider(p.id))
        .addEntry(
          await fresh(p),
          type: direction == LoanDirection.given
              ? LedgerEntryType.gave
              : LedgerEntryType.borrowed,
          amount: 10000,
          date: _date,
          note: 'Rahul loan',
          transactionRef: loan.id,
        );
    container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
    await settle();
    return loan;
  }

  Future<String> bank() async =>
      (await container
              .read(accountRepositoryProvider)
              .createAccount(
                name: 'HDFC',
                type: AccountType.bank,
                openingBalance: 100000,
                colorValue: 0,
              ))
          .id;

  Future<List<Installment>> live(Loan loan) async => (await container.read(
    installmentsStreamProvider(loan.scheduleId).future,
  )).toList()..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

  group('reproduction — pre-change behaviour', () {
    test('old web Loan I lent: ledger 10,000 + Loan 10,000 → the pre-change '
        'statement arithmetic showed 20,000', () async {
      final rahul = await person('Rahul');
      await oldWebLoan(rahul, LoanDirection.given);
      final ledgerBalance = (await fresh(rahul)).currentBalance;
      expect(ledgerBalance, 10000);
      final preChange = PersonLoanLedgerSummary(
        ledgerBalance: ledgerBalance,
        loanGivenTotal: 10000,
        loanGivenOutstanding: 10000,
        loanTakenTotal: 0,
        loanTakenOutstanding: 0,
      );
      expect(preChange.theyOweYou, 20000);
    });

    test('old web Loan I borrowed → pre-change showed I owe 20,000', () async {
      final rahul = await person('Rahul');
      await oldWebLoan(rahul, LoanDirection.taken);
      final preChange = PersonLoanLedgerSummary(
        ledgerBalance: (await fresh(rahul)).currentBalance,
        loanGivenTotal: 0,
        loanGivenOutstanding: 0,
        loanTakenTotal: 10000,
        loanTakenOutstanding: 10000,
      );
      expect(preChange.youOweThem, 20000);
    });

    test(
      'new wizard Loan: currentBalance (the pre-change list source) is 0',
      () async {
        final rahul = await person('Rahul');
        await wizardLoan(rahul, LoanDirection.given, 'fl-repro-0001');
        expect((await fresh(rahul)).currentBalance, 0);
        expect((await fresh(rahul)).isCreditor, isFalse);
      },
    );
  });

  group('canonical rule, live', () {
    test(
      'A/C — old web Loan counts once: list, totals, statement card',
      () async {
        final rahul = await person('Rahul');
        await oldWebLoan(rahul, LoanDirection.given);
        final p = container.read(personPositionProvider(rahul.id));
        expect([p.directBalance, p.loanReceivable, p.net], [0, 10000, 10000]);
        expect(container.read(creditorsProvider).map((x) => x.id), [rahul.id]);
        expect(container.read(totalReceivableProvider), 10000);
        final card = container.read(personLoanLedgerSummaryProvider(rahul.id));
        expect([card.theyOweYou, card.net], [10000, 10000]);
      },
    );

    test('B — old web borrowed Loan counts once', () async {
      final rahul = await person('Rahul');
      await oldWebLoan(rahul, LoanDirection.taken);
      expect(container.read(personPositionProvider(rahul.id)).iOwe, 10000);
      expect(container.read(debtorsProvider).map((x) => x.id), [rahul.id]);
      expect(container.read(totalPayableProvider), 10000);
    });

    test('D — new wizard Loan appears under "owes you"', () async {
      final rahul = await person('Rahul');
      await wizardLoan(rahul, LoanDirection.given, 'fl-canon-0001');
      expect(container.read(creditorsProvider).map((x) => x.id), [rahul.id]);
      expect(container.read(totalReceivableProvider), 10000);
    });

    test(
      'G — direct 2,000 + Loan 10,000 = 12,000; ledger part independent',
      () async {
        final rahul = await person('Rahul');
        await container
            .read(ledgerRepositoryProvider(rahul.id))
            .addEntry(
              await fresh(rahul),
              type: LedgerEntryType.gave,
              amount: 2000,
              date: _date,
            );
        await wizardLoan(rahul, LoanDirection.given, 'fl-canon-0002');
        final p = container.read(personPositionProvider(rahul.id));
        expect(
          [p.directBalance, p.loanReceivable, p.net],
          [2000, 10000, 12000],
        );
      },
    );

    test('E/F — repayment 4,000 lowers it to 6,000 live; reversing restores '
        'it once; no ledger entry written', () async {
      final rahul = await person('Rahul');
      final account = await bank();
      final loan = await wizardLoan(
        rahul,
        LoanDirection.given,
        'fl-pay-00001',
        accountId: account,
      );
      final paid = await container
          .read(loanAdvancePaymentRepositoryProvider)
          .record(
            loan: loan,
            scheduleInstallments: await live(loan),
            accountId: account,
            amount: 4000,
            date: _date,
            idempotencyKey: 'fl-pay-00001-p',
            includeUpcomingInstallments: true,
          );
      await settle();
      expect(container.read(personPositionProvider(rahul.id)).owesMe, 6000);
      await container
          .read(loanAdvancePaymentRepositoryProvider)
          .reversePayment(
            loan: loan,
            transactionId: paid.transactionId,
            paymentIds: paid.paymentIds,
            installmentIds: paid.installmentIds,
            reversalIdempotencyKey: 'fl-pay-00001-r',
          );
      await settle();
      expect(container.read(personPositionProvider(rahul.id)).owesMe, 10000);
      expect(
        await container.read(ledgerRepositoryProvider(rahul.id)).getAll(),
        isEmpty,
      );
    });

    test(
      'Borrow More raises what I owe; reversed origination removes it',
      () async {
        final rahul = await person('Rahul');
        final account = await bank();
        final loan = await wizardLoan(
          rahul,
          LoanDirection.taken,
          'fl-more-0001',
          accountId: account,
        );
        await container
            .read(loanAdvancePaymentRepositoryProvider)
            .recordAdditionalDisbursement(
              loan: loan,
              scheduleInstallments: await live(loan),
              accountId: account,
              amount: 2000,
              date: _date,
              idempotencyKey: 'fl-more-0001-d',
            );
        await settle();
        expect(
          container.read(personPositionProvider(rahul.id)).iOwe,
          closeTo(12000, 0.01),
        );

        final other = await wizardLoan(
          rahul,
          LoanDirection.given,
          'fl-rev-00001',
          accountId: account,
        );
        expect(other.personId, rahul.id);
        await container
            .read(loanRepositoryProvider)
            .reverseOrigination('fl-rev-00001');
        await settle();
        expect(
          container.read(personPositionProvider(rahul.id)).loanReceivable,
          0,
        );
      },
    );

    test('payer-only link is not a Loan with that person', () async {
      final rahul = await person('Rahul');
      await container
          .read(loanRepositoryProvider)
          .createLoan(
            loanAmount: 50000,
            loanDate: _date,
            repaymentType: LoanRepaymentType.installment,
            installmentFrequency: ScheduleType.monthly,
            installmentCount: 5,
            category: LoanCategory.institutional,
            institutionName: 'Axis',
            payerPersonId: rahul.id,
            direction: LoanDirection.taken,
          );
      await settle();
      expect(container.read(personPositionProvider(rahul.id)).net, 0);
      expect(container.read(personLoanLedgerSummaryProvider(rahul.id)).net, 0);
    });
  });

  group('H — settlement never touches Loan debt', () {
    test('Settle All on a person with an old web Loan + a direct 500 settles '
        'only the 500, in the right direction', () async {
      final rahul = await person('Rahul');
      final loan = await oldWebLoan(rahul, LoanDirection.given);
      // Direct: I owe Rahul 500 (they paid for my coffee).
      await container
          .read(ledgerRepositoryProvider(rahul.id))
          .addEntry(
            await fresh(rahul),
            type: LedgerEntryType.borrowed,
            amount: 500,
            date: _date,
          );
      await settle();
      final before = container.read(personPositionProvider(rahul.id));
      expect([before.directBalance, before.loanReceivable], [-500, 10000]);

      await container
          .read(expenseRepositoryProvider)
          .settleAcrossPending(
            person: await fresh(rahul),
            pending: const [],
            amount: before.directBalance.abs(),
            date: _date,
            installmentPaymentRepositoryFor: (_, _) =>
                throw StateError('no split installments here'),
            legacyLoanLedger: before.legacyLoanLedger,
          );
      await settle();
      final after = container.read(personPositionProvider(rahul.id));
      expect(after.directBalance, 0);
      expect(after.loanReceivable, 10000);
      expect(after.net, 10000);
      expect(loan.personId, rahul.id);
    });
  });
}
