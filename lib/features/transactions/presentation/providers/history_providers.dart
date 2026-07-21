import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../domain/history_builder.dart';
import '../../domain/history_entry.dart';
import 'transaction_providers.dart';

/// Every installment payment recorded across a loan/EMI's whole schedule —
/// fans out over the schedule's installments (payments are stored per
/// installment, not per schedule), mirrors `person_timeline_providers.dart`'s
/// `_loanPaymentsProvider`.
final _installmentPaymentsForScheduleProvider =
    Provider.autoDispose.family<List<InstallmentPayment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return [
    for (final installment in installments)
      ...ref.watch(installmentPaymentsStreamProvider((scheduleId: scheduleId, installmentId: installment.id))).value ??
          const [],
  ];
});

/// The unified History feed — every plain transaction, split expense
/// (via its account-balance transaction), loan/bill/EMI payment, and money-
/// received receipt, newest first. The single place all of these get pulled
/// together (mirrors `personTimelineProvider` doing the same for one
/// person), so the History screen's filters never disagree with each
/// feature's own list/detail screens.
final historyEntriesProvider = Provider<List<HistoryEntry>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  final loans = ref.watch(loansStreamProvider).value ?? const [];
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final emis = ref.watch(emisStreamProvider).value ?? const [];

  final loanData = [
    for (final loan in loans)
      LoanHistoryData(loan: loan, payments: ref.watch(_installmentPaymentsForScheduleProvider(loan.scheduleId))),
  ];
  final billData = [
    for (final bill in bills)
      BillHistoryData(bill: bill, payments: ref.watch(paymentsStreamProvider(bill.id)).value ?? const []),
  ];
  final emiData = [
    for (final emi in emis)
      EmiHistoryData(emi: emi, payments: ref.watch(_installmentPaymentsForScheduleProvider(emi.scheduleId))),
  ];
  final installmentsByScheduleId = {
    for (final expense in expenses)
      if (expense.isSplit && expense.scheduleId != null)
        expense.scheduleId!: ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [],
  };

  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  final accountNameById = {for (final a in accounts) a.id: a.name};
  final creditCardData = <CreditCardHistoryData>[];
  for (final card in cards) {
    final statements = ref.watch(statementsWithLiveTotalsProvider(card.id));
    creditCardData.add(
      CreditCardHistoryData(
        cardName: accountNameById[card.accountId] ?? 'Card',
        statements: statements,
        paymentsByStatementId: {
          for (final statement in statements)
            statement.id:
                ref.watch(statementPaymentsStreamProvider((cardId: card.id, statementId: statement.id))).value ??
                const [],
        },
      ),
    );
  }

  return HistoryBuilder.build(
    transactions: transactions,
    expenses: expenses,
    loans: loanData,
    bills: billData,
    emis: emiData,
    creditCards: creditCardData,
    installmentsByScheduleId: installmentsByScheduleId,
  );
});
