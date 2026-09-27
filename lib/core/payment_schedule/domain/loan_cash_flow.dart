import 'installment_payment.dart';

/// Whether Cash Flow / the dashboard financial views may count [payment]
/// from the payment schedule. Mirrors `lib/engines/loan-cash-flow.ts`'s
/// `countsFromSchedule` on Web exactly.
///
/// A modern Loan payment (`LoanAdvancePaymentRepository.record`) posts ONE
/// physical `Transaction` and stamps its id on every [InstallmentPayment] it
/// created, so that Transaction is what counts the money movement — the
/// schedule line must skip it. A legacy payment (recorded before Loans posted
/// Transactions) has `transactionId == null`: the schedule is then the ONLY
/// record of the money movement, so it still counts. Never matched by
/// amount/date.
bool countsFromSchedule(InstallmentPayment payment) =>
    payment.deletedAt == null && payment.transactionId == null;
