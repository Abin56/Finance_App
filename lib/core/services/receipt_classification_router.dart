import '../../features/emi/domain/emi.dart';
import '../../features/expense/data/expense_repository.dart';
import '../../features/expense/domain/expense.dart';
import '../../features/expense/domain/expense_participant.dart';
import '../../features/lending/domain/loan.dart';
import '../../features/people/data/ledger_repository.dart';
import '../../features/people/domain/ledger_entry_type.dart';
import '../../features/people/domain/person.dart';
import '../../features/savings/data/savings_repository.dart';
import '../../features/savings/domain/savings_goal.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/domain/transaction_type.dart';
import '../errors/app_exception.dart';
import '../models/receipt_purpose.dart';
import '../payment_schedule/data/installment_payment_repository.dart';
import '../payment_schedule/domain/installment.dart';

/// Everything `ReceiptClassificationRouter.classify` might need to update,
/// depending on which `ReceiptPurpose.targetKind` the caller picked. Only
/// the fields matching that target kind need to be supplied — the router
/// validates this and throws `AppException` if a required one is missing,
/// rather than silently no-oping.
class ReceiptClassificationTarget {
  const ReceiptClassificationTarget({
    this.person,
    this.loan,
    this.emi,
    this.installment,
    this.installmentPaymentRepository,
    this.savingsRepository,
    this.savingsGoal,
    this.expense,
    this.expenseParticipant,
    this.expenseRepository,
  });

  /// Required for [ReceiptTargetKind.person] (and implicitly satisfied
  /// whenever [loan] is supplied, since a loan always belongs to a person).
  final Person? person;

  /// Required for [ReceiptTargetKind.loanInstallment].
  final Loan? loan;

  /// Required for [ReceiptTargetKind.emiInstallment].
  final Emi? emi;

  /// Required alongside [loan] or [emi] — the specific installment being
  /// paid toward. Also required alongside [expense]/[expenseParticipant] for
  /// [ReceiptTargetKind.splitExpenseParticipant] (that participant's own
  /// tracking installment).
  final Installment? installment;

  /// Required alongside [installment] — scoped to that installment's
  /// schedule, same shape `RecordEmiPaymentSheet` already resolves via
  /// `installmentPaymentRepositoryProvider`.
  final InstallmentPaymentRepository? installmentPaymentRepository;

  /// Required for [ReceiptTargetKind.savingsGoal], alongside [savingsGoal].
  final SavingsRepository? savingsRepository;

  /// Required for [ReceiptTargetKind.savingsGoal].
  final SavingsGoal? savingsGoal;

  /// Required for [ReceiptTargetKind.splitExpenseParticipant], alongside
  /// [expenseParticipant]/[installment]/[installmentPaymentRepository] —
  /// settling routes through `ExpenseRepository.settleParticipant` so no
  /// settlement logic is duplicated here.
  final Expense? expense;

  /// Required for [ReceiptTargetKind.splitExpenseParticipant].
  final ExpenseParticipant? expenseParticipant;

  /// Required for [ReceiptTargetKind.splitExpenseParticipant].
  final ExpenseRepository? expenseRepository;
}

/// Routes a single "money received" event to whichever existing module(s)
/// its [ReceiptPurpose] implies, so every purpose funnels through one
/// reusable engine instead of each feature hand-rolling its own "why did I
/// get this money" handling. Every receipt always posts a [Transaction]
/// (money landing in an account); [ReceiptPurpose.targetKind] then decides
/// what *else* happens:
///
///  - [ReceiptTargetKind.person] / a person-linked loan installment: also
///    posts a `LedgerEntry` so the person's pending amount drops.
///  - [ReceiptTargetKind.loanInstallment] / [ReceiptTargetKind.emiInstallment]:
///    also records an `InstallmentPayment` against the linked schedule.
///  - [ReceiptTargetKind.savingsGoal]: also contributes to the goal.
///  - [ReceiptTargetKind.splitExpenseParticipant]: delegates entirely to
///    `ExpenseRepository.settleParticipant`, which records the
///    `InstallmentPayment` against that participant's tracking installment
///    and posts the reversing `LedgerEntry` — no settlement logic lives here.
///  - [ReceiptTargetKind.none]: transaction only (gift, salary, refund,
///    cashback, investment return, interest received, tip, wallet deposit,
///    personal loan received, other).
///
/// No new financial math lives here — every effect is a call into an
/// existing repository (`TransactionRepository`, `LedgerRepository`,
/// `InstallmentPaymentRepository`, `SavingsRepository`), so this class is
/// pure dispatch and stays reusable by any future module that needs to
/// classify an incoming payment the same way.
class ReceiptClassificationRouter {
  const ReceiptClassificationRouter({
    required this.transactionRepository,
    required this.ledgerRepositoryFor,
  });

  final TransactionRepository transactionRepository;

  /// Resolves a `LedgerRepository` scoped to a given person id — supplied
  /// by the provider layer, mirrors `ExpenseRepository`'s dependency shape.
  final LedgerRepository Function(String personId) ledgerRepositoryFor;

  Future<Transaction> classify({
    required ReceiptPurpose purpose,
    required double amount,
    required DateTime date,
    required String accountId,
    required String categoryId,
    ReceiptClassificationTarget target = const ReceiptClassificationTarget(),
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('Amount must be greater than 0');
    }
    _validateTarget(purpose, target);

    final transaction = await transactionRepository.createTransaction(
      type: TransactionType.income,
      amount: amount,
      dateTime: date,
      accountId: accountId,
      categoryId: categoryId,
      notes: note.isEmpty ? purpose.label : note,
      receiptPurpose: purpose.name,
    );

    switch (purpose.targetKind) {
      case ReceiptTargetKind.person:
        await _postLedgerEntry(target.person!, amount, date, note, transaction.id);

      case ReceiptTargetKind.loanInstallment:
      case ReceiptTargetKind.emiInstallment:
        await target.installmentPaymentRepository!.recordPayment(
          target.installment!,
          amount: amount,
          date: date,
          note: note,
        );
        if (target.loan != null) {
          await _postLedgerEntry(target.person!, amount, date, note, transaction.id);
        }

      case ReceiptTargetKind.savingsGoal:
        await target.savingsRepository!.contribute(target.savingsGoal!, amount);

      case ReceiptTargetKind.splitExpenseParticipant:
        await target.expenseRepository!.settleParticipant(
          expense: target.expense!,
          participant: target.expenseParticipant!,
          installment: target.installment!,
          installmentPaymentRepository: target.installmentPaymentRepository!,
          amount: amount,
          date: date,
          note: note,
        );

      case ReceiptTargetKind.none:
        break;
    }

    return transaction;
  }

  Future<void> _postLedgerEntry(
    Person person,
    double amount,
    DateTime date,
    String note,
    String transactionRef,
  ) {
    return ledgerRepositoryFor(person.id).addEntry(
      person,
      type: LedgerEntryType.receivedBack,
      amount: amount,
      date: date,
      note: note,
      transactionRef: transactionRef,
    );
  }

  void _validateTarget(ReceiptPurpose purpose, ReceiptClassificationTarget target) {
    switch (purpose.targetKind) {
      case ReceiptTargetKind.person:
        if (target.person == null) {
          throw AppException('${purpose.label} needs a person to record it against');
        }
      case ReceiptTargetKind.loanInstallment:
        if (target.loan == null || target.installment == null || target.installmentPaymentRepository == null) {
          throw AppException('${purpose.label} needs a loan and a payment to record it against');
        }
        if (target.person == null) {
          throw AppException('${purpose.label} needs the loan\'s person to update their amount left');
        }
      case ReceiptTargetKind.emiInstallment:
        if (target.emi == null || target.installment == null || target.installmentPaymentRepository == null) {
          throw AppException('${purpose.label} needs an EMI and a payment to record it against');
        }
      case ReceiptTargetKind.savingsGoal:
        if (target.savingsGoal == null || target.savingsRepository == null) {
          throw AppException('${purpose.label} needs a savings goal to record it against');
        }
      case ReceiptTargetKind.splitExpenseParticipant:
        if (target.expense == null ||
            target.expenseParticipant == null ||
            target.installment == null ||
            target.installmentPaymentRepository == null ||
            target.expenseRepository == null) {
          throw AppException('${purpose.label} needs a shared expense and person to record it against');
        }
      case ReceiptTargetKind.none:
        break;
    }
  }
}
