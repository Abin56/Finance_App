import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/lending/data/loan_advance_payment_repository.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_balance_sheet.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_financial_summary.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decision 5 — extra principal is derived from persisted payment records.
/// Every re-plan (a later extra-principal payment, Borrow/Lend More, Edit
/// terms) and every displayed "principal remaining" must subtract ALL active
/// extra principal. Before: each re-plan subtracted only its own triggering
/// prepayment, so ₹12,000 − EMI 1,000 − extra 3,000 − EMI 1,000 − extra 2,000
/// re-planned to ₹8,000 remaining (and the tenure went UP) instead of ₹5,000.
/// Same numbers as Web's `tests/integration/loan-principal-prepayment.test.ts`.
const _uid = 'test-uid';

void main() {
  late FakeFirebaseFirestore firestore;
  late LoanAdvancePaymentRepository payments;
  late LoanRepository loans;
  late AccountRepository accounts;

  CollectionReference<Map<String, dynamic>> col(String name) =>
      firestore.collection('users').doc(_uid).collection(name);
  CollectionReference<Installment> installmentsCol(String scheduleId) => col('paymentSchedules')
      .doc(scheduleId)
      .collection('installments')
      .withConverter<Installment>(fromFirestore: Installment.fromFirestore, toFirestore: (i, _) => i.toFirestore());

  setUp(() {
    firestore = FakeFirebaseFirestore();
    accounts = AccountRepository(
      col('accounts').withConverter<Account>(fromFirestore: Account.fromFirestore, toFirestore: (a, _) => a.toFirestore()),
    );
    loans = LoanRepository(
      col('loans').withConverter<Loan>(fromFirestore: Loan.fromFirestore, toFirestore: (l, _) => l.toFirestore()),
      PaymentScheduleRepository(
        col('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        ),
      ),
      (scheduleId) => InstallmentRepository(installmentsCol(scheduleId)),
    );
    payments = LoanAdvancePaymentRepository(firestore: firestore, uid: _uid);
  });

  Future<List<Installment>> live(Loan loan) async {
    final snap = await installmentsCol(loan.scheduleId).where('deletedAt', isNull: true).get();
    return snap.docs.map((d) => d.data()).toList()..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  double unpaidTail(List<Installment> installments) =>
      installments.where((i) => i.amountPaid == 0).fold(0.0, (s, i) => s + i.amountDue);

  Future<double> displayedPrincipal(Loan loan) async {
    final fresh = (await loans.getByKey(loan.id))!;
    return LoanFinancialSummary.from(
      installments: await live(loan),
      originalPrincipal: fresh.loanAmount,
      principalPrepaid: await loans.activePrincipalPrepaid(loan.scheduleId),
    ).principalRemaining;
  }

  Future<(Loan, Account)> setup() async {
    final acct = await accounts.createAccount(name: 'W', type: AccountType.bank, openingBalance: 1e6, colorValue: 0);
    final loan = await loans.createLoan(
      loanAmount: 12000,
      loanDate: DateTime(2026, 1, 1),
      repaymentType: LoanRepaymentType.installment,
      direction: LoanDirection.taken,
      category: LoanCategory.institutional,
      institutionName: 'B',
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
    );
    return (loan, acct);
  }

  Future<void> twoExtraPrincipalPayments(Loan loan, Account acct) async {
    await payments.record(loan: loan, scheduleInstallments: await live(loan), accountId: acct.id, amount: 1000 + 3000, date: DateTime(2026, 1, 15), idempotencyKey: 'p1');
    final installments = await live(loan);
    final due = installments.firstWhere((i) => i.amountPaid == 0).amountDue;
    expect(due, 1000);
    await payments.record(loan: loan, scheduleInstallments: installments, accountId: acct.id, amount: due + 2000, date: DateTime(2026, 1, 16), idempotencyKey: 'p2');
  }

  test('a second extra-principal payment keeps the first one (₹5,000 left, not ₹8,000)', () async {
    final (loan, acct) = await setup();
    await twoExtraPrincipalPayments(loan, acct);
    expect(unpaidTail(await live(loan)), closeTo(5000, 0.01));
    expect(await loans.activePrincipalPrepaid(loan.scheduleId), 5000);
    expect(await displayedPrincipal(loan), closeTo(5000, 0.01));
    final fresh = (await loans.getByKey(loan.id))!;
    expect(fresh.installmentCount, 7, reason: '2 paid + ₹5,000 / ₹1,000 = 5 more — never more than before');
    expect(fresh.loanAmount, 12000, reason: 'an extra-principal payment never changes loanAmount');
  });

  test('Borrow More after extra principal adds on top of the reduced principal', () async {
    final (loan, acct) = await setup();
    await twoExtraPrincipalPayments(loan, acct);
    final fresh = (await loans.getByKey(loan.id))!;
    await payments.recordAdditionalDisbursement(loan: fresh, scheduleInstallments: await live(loan), accountId: acct.id, amount: 4000, date: DateTime(2026, 1, 20), idempotencyKey: 'd1');
    expect(unpaidTail(await live(loan)), closeTo(9000, 0.01), reason: '5,000 + 4,000 — the 5,000 of extra principal is not given back');
    expect(await displayedPrincipal(loan), closeTo(9000, 0.01));
  });

  test('editing terms after extra principal re-plans from the reduced principal', () async {
    final (loan, acct) = await setup();
    await twoExtraPrincipalPayments(loan, acct);
    final fresh = (await loans.getByKey(loan.id))!;
    await loans.editLoanTerms(fresh, currentInstallments: await live(loan), installmentFrequency: ScheduleType.monthly, newInstallmentCount: 12);
    expect(unpaidTail(await live(loan)), closeTo(5000, 0.01));
  });

  test('reversing the second extra-principal payment restores ₹8,000 exactly', () async {
    final (loan, acct) = await setup();
    await payments.record(loan: loan, scheduleInstallments: await live(loan), accountId: acct.id, amount: 4000, date: DateTime(2026, 1, 15), idempotencyKey: 'p1');
    final second = await payments.record(loan: loan, scheduleInstallments: await live(loan), accountId: acct.id, amount: 3000, date: DateTime(2026, 1, 16), idempotencyKey: 'p2');
    await payments.reversePayment(
      loan: loan,
      transactionId: second.transactionId,
      paymentIds: second.paymentIds,
      installmentIds: second.installmentIds,
      overflowPaymentId: second.overflowPaymentId,
      overflowInstallmentId: second.overflowInstallmentId,
      reversalIdempotencyKey: 'p2-undo',
    );
    expect(await loans.activePrincipalPrepaid(loan.scheduleId), 3000);
    expect(await displayedPrincipal(loan), closeTo(8000, 0.01));
  });

  group('LoanBalanceSheet / Net Worth (Decision 6)', () {
    test('borrowed principal is a liability, lent principal a receivable, card-owned EMI excluded', () {
      final sheet = LoanBalanceSheet.from(
        loans: const [
          LoanPrincipalPosition(direction: LoanDirection.taken, outstandingPrincipal: 10000),
          LoanPrincipalPosition(direction: LoanDirection.given, outstandingPrincipal: 25000),
        ],
        emis: const [
          EmiPrincipalPosition(outstandingPrincipal: 30000, ownedByTrackedCard: false),
          EmiPrincipalPosition(outstandingPrincipal: 60000, ownedByTrackedCard: true),
        ],
      );
      expect(sheet.borrowedPrincipal, 10000);
      expect(sheet.lentPrincipal, 25000);
      expect(sheet.emiPrincipal, 30000);
      expect(sheet.cardOwnedEmiPrincipal, 60000);
      // accounts 100,000 + owed to me 25,000 − owed by me (10,000 + 30,000)
      expect(netWorthWithLoans(100000, sheet), 85000);
    });

    test('borrowing ₹10,000 into an account does not change Net Worth; lending ₹10,000 out does not either', () {
      const accountsBefore = 50000.0;
      final borrowed = LoanBalanceSheet.from(
        loans: const [LoanPrincipalPosition(direction: LoanDirection.taken, outstandingPrincipal: 10000)],
        emis: const [],
      );
      expect(netWorthWithLoans(accountsBefore + 10000, borrowed), accountsBefore);
      final lent = LoanBalanceSheet.from(
        loans: const [LoanPrincipalPosition(direction: LoanDirection.given, outstandingPrincipal: 10000)],
        emis: const [],
      );
      expect(netWorthWithLoans(accountsBefore - 10000, lent), accountsBefore);
    });
  });
}
