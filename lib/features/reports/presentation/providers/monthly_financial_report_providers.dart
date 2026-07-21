import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';

/// Report-scoped aggregations for the Monthly Financial Report — every
/// provider composes existing streams/fields (`Installment.amountPaid`,
/// `Emi.processingFee`/`insuranceAmount`/`extraCharges`, `Bill.amountPaid`)
/// rather than reimplementing any payment/status math.
typedef DateRangeKey = ({DateTime start, DateTime end});

/// Sum of `amountPaid` across every active EMI's installments whose due
/// date falls within [range] — a period-scoped variant of
/// [emiPaidThisMonthProvider], which is this-month-only.
final emiPaidForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final emis = ref.watch(activeEmisProvider);
  var total = 0.0;
  for (final emi in emis) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (i.dueDate.isBefore(range.start) || i.dueDate.isAfter(range.end)) continue;
      total += i.amountPaid;
    }
  }
  return total;
});

/// Sum of `amountPaid` across every active Loan's installments whose due
/// date falls within [range].
final loanPaidForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final loans = ref.watch(activeLoansProvider);
  var total = 0.0;
  for (final loan in loans) {
    final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (i.dueDate.isBefore(range.start) || i.dueDate.isAfter(range.end)) continue;
      total += i.amountPaid;
    }
  }
  return total;
});

/// Sum of `Bill.amountPaid` across every bill whose due date falls within
/// [range] — "Total Bills Paid" for an arbitrary report period (as opposed
/// to [paidBillsProvider], which has no date filter).
final billsPaidForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  var total = 0.0;
  for (final b in bills) {
    if (b.dueDate.isBefore(range.start) || b.dueDate.isAfter(range.end)) continue;
    total += b.amountPaid;
  }
  return total;
});

/// Sum of `Statement.amountPaid` across every card's statements whose due
/// date falls within [range] — "Credit Card Bills Paid".
final creditCardBillsPaidForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var total = 0.0;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    for (final s in statements) {
      if (s.dueDate.isBefore(range.start) || s.dueDate.isAfter(range.end)) continue;
      total += s.amountPaid;
    }
  }
  return total;
});

/// Credit Utilization % — total outstanding across every card/group divided
/// by total credit limit, guarded against a zero denominator. Both sides use
/// [totalCreditLimitProvider]/[totalCreditCardOutstandingProvider], which
/// count a shared credit limit's [SharedCreditLimit.creditLimit] exactly
/// once — summing raw [CreditCardProfile.creditLimit] here would
/// double-count a shared Visa/RuPay pair's limit and understate the
/// percentage.
final creditUtilizationPercentProvider = Provider<double>((ref) {
  final cards = ref.watch(activeCreditCardsProvider);
  if (cards.isEmpty) return 0;
  final totalLimit = ref.watch(totalCreditLimitProvider);
  if (totalLimit == 0) return 0;
  final outstanding = ref.watch(totalCreditCardOutstandingProvider);
  return (outstanding / totalLimit) * 100;
});

/// Sum of `Emi.insuranceAmount` across EMIs created within [range] — a
/// one-time, informational charge (not amortized), so it's attributed to
/// the EMI's creation date.
final insuranceChargesForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis
      .where((e) => !e.createdAt.isBefore(range.start) && !e.createdAt.isAfter(range.end))
      .fold(0.0, (sum, e) => sum + e.insuranceAmount);
});

/// Sum of `Emi.processingFee` across EMIs created within [range].
final processingFeesForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis
      .where((e) => !e.createdAt.isBefore(range.start) && !e.createdAt.isAfter(range.end))
      .fold(0.0, (sum, e) => sum + e.processingFee);
});

/// Sum of `Emi.extraCharges` across EMIs created within [range].
final otherChargesForRangeProvider = Provider.autoDispose.family<double, DateRangeKey>((ref, range) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis
      .where((e) => !e.createdAt.isBefore(range.start) && !e.createdAt.isAfter(range.end))
      .fold(0.0, (sum, e) => sum + e.extraCharges);
});
