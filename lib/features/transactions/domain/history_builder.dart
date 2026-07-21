import 'package:flutter/material.dart';

import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';
import '../../../core/router/app_routes.dart';
import '../../bills/domain/bill.dart';
import '../../bills/domain/payment_record.dart';
import '../../credit_cards/domain/statement.dart';
import '../../credit_cards/domain/statement_payment.dart';
import '../../../shared/domain/transaction_kind.dart';
import '../../emi/domain/emi.dart';
import '../../expense/domain/expense.dart';
import '../../lending/domain/loan.dart';
import 'history_entry.dart';
import 'transaction.dart';
import 'transaction_type.dart';

/// Every payment recorded against one [Bill]'s current occurrence, supplied
/// by the caller (the provider layer) — this pure builder does no I/O.
class BillHistoryData {
  const BillHistoryData({required this.bill, required this.payments});

  final Bill bill;
  final List<PaymentRecord> payments;
}

/// Every installment payment recorded against one [Loan]'s schedule.
class LoanHistoryData {
  const LoanHistoryData({required this.loan, required this.payments});

  final Loan loan;
  final List<InstallmentPayment> payments;
}

/// Every installment payment recorded against one [Emi]'s schedule.
class EmiHistoryData {
  const EmiHistoryData({required this.emi, required this.payments});

  final Emi emi;
  final List<InstallmentPayment> payments;
}

/// One card's materialized statements plus every payment recorded against
/// each — Part 3's "Purchase -> Statement Generated -> Friend Paid ->
/// Statement Paid" timeline. [paymentsByStatementId] mirrors
/// [BillHistoryData.payments]' per-owner shape, just keyed by statement
/// since payments live in a per-statement subcollection.
class CreditCardHistoryData {
  const CreditCardHistoryData({required this.cardName, required this.statements, required this.paymentsByStatementId});

  final String cardName;
  final List<Statement> statements;
  final Map<String, List<StatementPayment>> paymentsByStatementId;
}

/// Folds every money-moving feature into one chronological [HistoryEntry]
/// list — the single place the unified History screen's "All / Split
/// expenses / Transactions / Loans / Bills / EMI / Money received" filters
/// get their data, so it can never disagree feature-by-feature with each
/// module's own screen. Every field here is read from an already-loaded
/// stream; no new business logic (payment application, balance math, status
/// derivation) is invented — this only labels and normalizes.
abstract class HistoryBuilder {
  HistoryBuilder._();

  static List<HistoryEntry> build({
    required List<Transaction> transactions,
    required List<Expense> expenses,
    required List<LoanHistoryData> loans,
    required List<BillHistoryData> bills,
    required List<EmiHistoryData> emis,
    List<CreditCardHistoryData> creditCards = const [],
    Map<String, List<Installment>> installmentsByScheduleId = const {},
    bool includeDeleted = false,
  }) {
    final splitExpenseByTransactionId = {for (final e in expenses) if (e.isSplit) e.transactionId: e};

    final entries = <HistoryEntry>[
      for (final transaction in transactions)
        if (includeDeleted || !transaction.isDeleted)
          _fromTransaction(
            transaction,
            splitExpense: splitExpenseByTransactionId[transaction.id],
            installmentsByScheduleId: installmentsByScheduleId,
          ),
      for (final loanData in loans) ..._fromLoan(loanData, includeDeleted: includeDeleted),
      for (final billData in bills) ..._fromBill(billData, includeDeleted: includeDeleted),
      for (final emiData in emis) ..._fromEmi(emiData, includeDeleted: includeDeleted),
      for (final cardData in creditCards) ..._fromCreditCard(cardData, includeDeleted: includeDeleted),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  static HistoryEntry _fromTransaction(
    Transaction transaction, {
    required Expense? splitExpense,
    required Map<String, List<Installment>> installmentsByScheduleId,
  }) {
    final isMoneyReceived = transaction.receiptPurpose != null;
    final category = splitExpense != null
        ? HistoryCategory.splitExpense
        : isMoneyReceived
            ? HistoryCategory.moneyReceived
            : HistoryCategory.transaction;
    final isCredit = transaction.type == TransactionType.income;

    // A transfer leg overrides every other classification — moving money
    // between the user's own accounts is never "my expense"/"my income"
    // even though it carries a TransactionType direction, and can't itself
    // be a split expense (see `Expense.isSplit`'s own transaction, which is
    // never a transfer leg).
    final kind = transaction.isTransfer
        ? TransactionKind.transfer
        : splitExpense != null
            ? TransactionKind.splitExpense
            : isCredit
                ? TransactionKind.myIncome
                : TransactionKind.myExpense;

    return HistoryEntry(
      id: 'txn-${transaction.id}',
      date: transaction.dateTime,
      title: transaction.type.label,
      subtitle: transaction.notes,
      amount: transaction.amount,
      isCredit: isCredit,
      category: category,
      icon: transaction.type.icon,
      kind: kind,
      routePath: '${AppRoutes.transactions}/${transaction.id}',
      splitExpenseDetail:
          splitExpense == null ? null : splitExpenseDetailFor(splitExpense, installmentsByScheduleId),
      excludeFromCalculations: transaction.excludeFromCalculations,
      accountingMonth: transaction.accountingMonth,
    );
  }

  /// Computes a split [Expense]'s aggregate participant-count/amount-to-
  /// collect/status — public so any screen showing a split expense (History,
  /// Transaction Details) derives the exact same numbers, never a second
  /// copy of this math.
  static SplitExpenseHistoryDetail splitExpenseDetailFor(
    Expense expense,
    Map<String, List<Installment>> installmentsByScheduleId,
  ) {
    final installments = installmentsByScheduleId[expense.scheduleId] ?? const <Installment>[];
    final amountToCollect = installments.fold(0.0, (sum, i) => sum + i.remainingAmount);
    final collected = installments.fold(0.0, (sum, i) => sum + i.amountPaid);

    final SplitExpenseHistoryStatus status;
    if (amountToCollect <= 0) {
      status = SplitExpenseHistoryStatus.completed;
    } else if (installments.any((i) => i.status == InstallmentStatus.overdue)) {
      status = SplitExpenseHistoryStatus.overdue;
    } else if (installments.any((i) => i.amountPaid > 0)) {
      status = SplitExpenseHistoryStatus.partial;
    } else {
      status = SplitExpenseHistoryStatus.pending;
    }

    return SplitExpenseHistoryDetail(
      participantCount: expense.participants.length,
      amountToCollect: amountToCollect,
      status: status,
      myShare: expense.myShare,
      collected: collected,
      shares: [
        for (final p in expense.participants)
          SplitShare(name: p.isMe ? 'You' : p.name, share: p.share, isMe: p.isMe),
      ]..sort((a, b) => a.isMe ? -1 : (b.isMe ? 1 : 0)),
    );
  }

  static List<HistoryEntry> _fromLoan(LoanHistoryData data, {required bool includeDeleted}) {
    final loan = data.loan;
    if (!includeDeleted && loan.isDeleted) return const [];

    return [
      for (final payment in data.payments)
        if (includeDeleted || !payment.isDeleted)
          HistoryEntry(
            id: 'loan-payment-${payment.id}',
            date: payment.date,
            title: loan.name?.isNotEmpty == true ? loan.name! : 'Loan payment',
            subtitle: payment.note,
            amount: payment.amount,
            isCredit: true,
            category: HistoryCategory.loan,
            icon: Icons.undo_rounded,
            kind: TransactionKind.loan,
            routePath: '${AppRoutes.loans}/${loan.id}',
          ),
    ];
  }

  static List<HistoryEntry> _fromBill(BillHistoryData data, {required bool includeDeleted}) {
    final bill = data.bill;
    if (!includeDeleted && bill.isDeleted) return const [];

    return [
      for (final payment in data.payments)
        if (includeDeleted || !payment.isDeleted)
          HistoryEntry(
            id: 'bill-payment-${payment.id}',
            date: payment.date,
            title: bill.name,
            subtitle: payment.note,
            amount: payment.amount,
            isCredit: false,
            category: HistoryCategory.bill,
            icon: Icons.receipt_long_outlined,
            kind: TransactionKind.bill,
            routePath: '${AppRoutes.bills}/${bill.id}',
          ),
    ];
  }

  /// One "Statement generated" entry per materialized [Statement], plus one
  /// "Statement paid" entry per [StatementPayment] — the two new legs of
  /// Part 3's "Purchase -> Statement Generated -> Friend Paid -> Statement
  /// Paid" timeline (the purchase and "Friend Paid" legs already exist via
  /// the ordinary transaction/split-settlement entries above; chronological
  /// sort is what keeps the whole chain reading in order, no separate
  /// threading mechanism needed).
  static List<HistoryEntry> _fromCreditCard(CreditCardHistoryData data, {required bool includeDeleted}) {
    final entries = <HistoryEntry>[];
    for (final statement in data.statements) {
      if (!includeDeleted && statement.isDeleted) continue;
      entries.add(
        HistoryEntry(
          id: 'statement-generated-${statement.id}',
          date: statement.generatedDate,
          title: '${data.cardName} statement generated',
          subtitle: 'Pay by ${statement.dueDate.day}/${statement.dueDate.month}',
          amount: statement.totalAmount,
          isCredit: false,
          category: HistoryCategory.statementGenerated,
          icon: Icons.receipt_long_outlined,
          kind: TransactionKind.creditCard,
          routePath: '${AppRoutes.creditCards}/${statement.cardId}/statements/${statement.id}',
        ),
      );
      final payments = data.paymentsByStatementId[statement.id] ?? const [];
      for (final payment in payments) {
        if (!includeDeleted && payment.isDeleted) continue;
        entries.add(
          HistoryEntry(
            id: 'statement-payment-${payment.id}',
            date: payment.date,
            title: '${data.cardName} statement paid',
            subtitle: payment.note,
            amount: payment.amount,
            isCredit: false,
            category: HistoryCategory.statementPaid,
            icon: Icons.check_circle_outline_rounded,
            kind: TransactionKind.creditCard,
            routePath: '${AppRoutes.creditCards}/${statement.cardId}/statements/${statement.id}',
          ),
        );
      }
    }
    return entries;
  }

  static List<HistoryEntry> _fromEmi(EmiHistoryData data, {required bool includeDeleted}) {
    final emi = data.emi;
    if (!includeDeleted && emi.isDeleted) return const [];

    return [
      for (final payment in data.payments)
        if (includeDeleted || !payment.isDeleted)
          HistoryEntry(
            id: 'emi-payment-${payment.id}',
            date: payment.date,
            title: emi.name,
            subtitle: payment.note,
            amount: payment.amount,
            isCredit: false,
            category: HistoryCategory.emi,
            icon: Icons.account_balance_wallet_outlined,
            kind: TransactionKind.emi,
            routePath: '${AppRoutes.emis}/${emi.id}',
          ),
    ];
  }
}
