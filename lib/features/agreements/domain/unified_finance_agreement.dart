import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../credit_cards/domain/card_emi_ownership.dart';
import '../../emi/domain/emi.dart';
import '../../lending/domain/loan.dart';
import '../../transactions/domain/transaction.dart';

enum UnifiedAgreementSourceType { loan, emi }

enum UnifiedAgreementKind { loan, installmentPurchase }

enum UnifiedAgreementDirection { borrowed, lent }

enum UnifiedRepaymentType { scheduled, oneTime, flexible }

enum UnifiedFundingSource { bank, financeCompany, creditCard, person, other }

enum UnifiedAgreementStatus { active, dueSoon, overdue, defaulted, closed }

/// Presentation-only contract. Adapting a record never writes Firestore.
class UnifiedFinanceAgreement {
  const UnifiedFinanceAgreement({
    required this.sourceType,
    required this.sourceId,
    required this.agreementKind,
    required this.direction,
    required this.repaymentType,
    required this.fundingSource,
    required this.personId,
    required this.creditCardId,
    required this.purchaseTransactionId,
    required this.linkedAccountId,
    required this.accountReference,
    required this.title,
    required this.providerName,
    required this.purchaseAmount,
    required this.downPayment,
    required this.originalPrincipal,
    required this.remainingPrincipal,
    required this.liabilityPrincipal,
    required this.receivablePrincipal,
    required this.cardOwnedLiability,
    required this.nonCardEmiLiability,
    required this.paidPrincipal,
    required this.paidInterest,
    required this.futureInterest,
    required this.interestRate,
    required this.interestType,
    required this.repaymentFrequency,
    required this.installmentCount,
    required this.installmentAmount,
    required this.nextDueDate,
    required this.status,
    required this.sourceStatus,
    required this.scheduleId,
    required this.createdAt,
  });
  final UnifiedAgreementSourceType sourceType;
  final String sourceId;
  final UnifiedAgreementKind agreementKind;
  final UnifiedAgreementDirection direction;
  final UnifiedRepaymentType repaymentType;
  final UnifiedFundingSource fundingSource;
  final String? personId;
  final String? creditCardId;
  final String? purchaseTransactionId;
  final String? linkedAccountId;
  final String? accountReference;
  final String title;
  final String? providerName;
  final double? purchaseAmount;
  final double? downPayment;
  final double originalPrincipal;
  final double remainingPrincipal;
  final double liabilityPrincipal;
  final double receivablePrincipal;
  final double cardOwnedLiability;
  final double nonCardEmiLiability;
  final double paidPrincipal;
  final double paidInterest;
  final double futureInterest;
  final double? interestRate;
  final String? interestType;
  final ScheduleType? repaymentFrequency;
  final int? installmentCount;
  final double? installmentAmount;
  final DateTime? nextDueDate;
  final UnifiedAgreementStatus status;
  final String sourceStatus;
  final String scheduleId;
  final DateTime createdAt;
}

typedef CardOwnershipContext = ({String cardAccountId, Transaction? purchase});

({
  double remaining,
  double paidPrincipal,
  double paidInterest,
  double futureInterest,
})
_money(List<Installment> installments) {
  var original = 0.0, remaining = 0.0, paidInterest = 0.0, futureInterest = 0.0;
  for (final item in installments.where((i) => i.deletedAt == null)) {
    final interest = item.interestPortion ?? 0;
    final principal =
        item.principalPortion ??
        (item.amountDue - interest).clamp(0, double.infinity);
    final interestPaid = item.amountPaid.clamp(0, interest);
    final principalPaid = (item.amountPaid - interest).clamp(0, principal);
    original += principal;
    remaining += principal - principalPaid;
    paidInterest += interestPaid;
    futureInterest += interest - interestPaid;
  }
  return (
    remaining: remaining.clamp(0, double.infinity),
    paidPrincipal: (original - remaining).clamp(0, double.infinity),
    paidInterest: paidInterest,
    futureInterest: futureInterest,
  );
}

({DateTime? next, bool overdue, bool dueSoon, double? amount}) _due(
  List<Installment> installments,
  DateTime now,
) {
  final live = installments
      .where((i) => i.deletedAt == null && !i.isSkipped)
      .toList();
  final unpaid = live.where((i) => i.amountPaid < i.amountDue).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final next = unpaid.isEmpty ? null : unpaid.first.dueDate;
  return (
    next: next,
    overdue: unpaid.any((i) => i.dueDate.isBefore(now)),
    dueSoon:
        next != null &&
        !next.isBefore(now) &&
        !next.isAfter(now.add(const Duration(days: 7))),
    amount: unpaid.isNotEmpty
        ? unpaid.first.amountDue
        : (live.isEmpty ? null : live.first.amountDue),
  );
}

UnifiedFinanceAgreement loanToUnifiedAgreement(
  Loan loan,
  List<Installment> installments, {
  CardOwnershipContext? ownership,
  DateTime? now,
}) {
  final money = _money(installments),
      due = _due(installments, now ?? DateTime.now());
  final remaining = installments.isEmpty ? loan.loanAmount : money.remaining;
  final borrowed = loan.direction.name == 'taken';
  final agreementKind =
      loan.agreementKind == LoanAgreementKind.installmentPurchase
      ? UnifiedAgreementKind.installmentPurchase
      : UnifiedAgreementKind.loan;
  final fundingSource = loan.fundingSource == null
      ? (loan.category.name == 'personal'
            ? UnifiedFundingSource.person
            : loan.institutionName != null
            ? UnifiedFundingSource.bank
            : UnifiedFundingSource.other)
      : UnifiedFundingSource.values.byName(loan.fundingSource!.name);
  final purchaseRepresented =
      fundingSource == UnifiedFundingSource.creditCard &&
      ownership != null &&
      emiPurchaseRepresentedOnCard(
        purchaseTransactionId: loan.purchaseTransactionId,
        purchase: ownership.purchase,
        cardAccountId: ownership.cardAccountId,
      );
  final cardOwned =
      borrowed &&
          fundingSource == UnifiedFundingSource.creditCard &&
          !purchaseRepresented &&
          !loan.isClosed
      ? remaining
      : 0.0;
  final ordinaryLiability =
      borrowed &&
          fundingSource != UnifiedFundingSource.creditCard &&
          !loan.isClosed
      ? remaining
      : 0.0;
  final status = loan.isClosed
      ? UnifiedAgreementStatus.closed
      : due.overdue
      ? UnifiedAgreementStatus.overdue
      : due.dueSoon
      ? UnifiedAgreementStatus.dueSoon
      : UnifiedAgreementStatus.active;
  return UnifiedFinanceAgreement(
    sourceType: UnifiedAgreementSourceType.loan,
    sourceId: loan.id,
    agreementKind: agreementKind,
    direction: borrowed
        ? UnifiedAgreementDirection.borrowed
        : UnifiedAgreementDirection.lent,
    repaymentType: loan.repaymentType.name == 'oneTime'
        ? UnifiedRepaymentType.oneTime
        : UnifiedRepaymentType.scheduled,
    fundingSource: fundingSource,
    personId: loan.personId,
    creditCardId: loan.linkedCreditCardId,
    purchaseTransactionId: loan.purchaseTransactionId,
    linkedAccountId: null,
    accountReference: loan.accountNumber,
    title: loan.name ?? loan.institutionName ?? 'Loan',
    providerName: loan.institutionName,
    purchaseAmount: loan.purchaseAmount,
    downPayment: loan.downPayment,
    originalPrincipal: loan.loanAmount,
    remainingPrincipal: remaining,
    liabilityPrincipal: ordinaryLiability + cardOwned,
    receivablePrincipal: !borrowed && !loan.isClosed ? remaining : 0,
    cardOwnedLiability: cardOwned,
    nonCardEmiLiability:
        agreementKind == UnifiedAgreementKind.installmentPurchase &&
            fundingSource != UnifiedFundingSource.creditCard
        ? ordinaryLiability
        : 0,
    paidPrincipal: installments.isEmpty ? 0 : money.paidPrincipal,
    paidInterest: money.paidInterest,
    futureInterest: money.futureInterest,
    interestRate: loan.interest?.ratePercent,
    interestType: loan.interest?.type.name,
    repaymentFrequency: loan.installmentFrequency,
    installmentCount: loan.installmentCount,
    installmentAmount: due.amount,
    nextDueDate: loan.repaymentType.name == 'oneTime' ? loan.dueDate : due.next,
    status: status,
    sourceStatus: loan.isClosed
        ? 'closed'
        : due.overdue
        ? 'overdue'
        : 'active',
    scheduleId: loan.scheduleId,
    createdAt: loan.createdAt,
  );
}

UnifiedFinanceAgreement emiToUnifiedAgreement(
  Emi emi,
  List<Installment> installments, {
  CardOwnershipContext? ownership,
  DateTime? now,
}) {
  final money = _money(installments),
      due = _due(installments, now ?? DateTime.now());
  final remaining = installments.isEmpty
      ? emi.principalAmount
      : money.remaining;
  final represented =
      ownership != null &&
      emiPurchaseRepresentedOnCard(
        purchaseTransactionId: emi.purchaseTransactionId,
        purchase: ownership.purchase,
        cardAccountId: ownership.cardAccountId,
      );
  final cardOwned =
      emi.linkedCreditCardId != null && !represented && !emi.isClosed
      ? remaining
      : 0.0;
  final nonCard = emi.linkedCreditCardId == null && !emi.isClosed
      ? remaining
      : 0.0;
  final status = emi.isClosed
      ? UnifiedAgreementStatus.closed
      : emi.isDefaulted
      ? UnifiedAgreementStatus.defaulted
      : due.overdue
      ? UnifiedAgreementStatus.overdue
      : due.dueSoon
      ? UnifiedAgreementStatus.dueSoon
      : UnifiedAgreementStatus.active;
  return UnifiedFinanceAgreement(
    sourceType: UnifiedAgreementSourceType.emi,
    sourceId: emi.id,
    agreementKind: UnifiedAgreementKind.installmentPurchase,
    direction: UnifiedAgreementDirection.borrowed,
    repaymentType: UnifiedRepaymentType.scheduled,
    fundingSource: emi.linkedCreditCardId != null
        ? UnifiedFundingSource.creditCard
        : emi.lenderName != null
        ? UnifiedFundingSource.financeCompany
        : UnifiedFundingSource.other,
    personId: null,
    creditCardId: emi.linkedCreditCardId,
    purchaseTransactionId: emi.purchaseTransactionId,
    linkedAccountId: null,
    accountReference: emi.autoDebitAccount,
    title: emi.name,
    providerName: emi.lenderName,
    purchaseAmount: null,
    downPayment: null,
    originalPrincipal: emi.principalAmount,
    remainingPrincipal: remaining,
    liabilityPrincipal: cardOwned + nonCard,
    receivablePrincipal: 0,
    cardOwnedLiability: cardOwned,
    nonCardEmiLiability: nonCard,
    paidPrincipal: installments.isEmpty ? 0 : money.paidPrincipal,
    paidInterest: money.paidInterest,
    futureInterest: money.futureInterest,
    interestRate: emi.interest?.ratePercent,
    interestType: emi.interest?.type.name,
    repaymentFrequency: emi.installmentFrequency,
    installmentCount: emi.installmentCount,
    installmentAmount: due.amount,
    nextDueDate: due.next,
    status: status,
    sourceStatus: emi.isClosed
        ? 'closed'
        : emi.isDefaulted
        ? 'defaulted'
        : due.overdue
        ? 'overdue'
        : 'active',
    scheduleId: emi.scheduleId,
    createdAt: emi.createdAt,
  );
}

List<UnifiedFinanceAgreement> sortUnifiedAgreements(
  Iterable<UnifiedFinanceAgreement> values,
) => values.toList()
  ..sort((a, b) {
    final byDue = (a.nextDueDate ?? DateTime(9999)).compareTo(
      b.nextDueDate ?? DateTime(9999),
    );
    if (byDue != 0) return byDue;
    final byType = a.sourceType.name.compareTo(b.sourceType.name);
    return byType != 0 ? byType : a.sourceId.compareTo(b.sourceId);
  });
