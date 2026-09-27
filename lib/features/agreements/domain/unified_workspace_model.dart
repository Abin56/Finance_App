import 'unified_finance_agreement.dart';

enum AgreementFilter { all, loan, installmentPurchase }

enum DirectionFilter { all, borrowed, lent }

enum FundingFilter { all, bank, financeCompany, creditCard, person, other }

enum StatusFilter { all, active, dueSoon, overdue, defaulted, closed }

enum UnifiedWorkspaceState { empty, noResults, ready }

class UnifiedWorkspaceFilters {
  const UnifiedWorkspaceFilters({
    this.search = '',
    this.agreement = AgreementFilter.all,
    this.direction = DirectionFilter.all,
    this.funding = FundingFilter.all,
    this.status = StatusFilter.all,
  });
  final String search;
  final AgreementFilter agreement;
  final DirectionFilter direction;
  final FundingFilter funding;
  final StatusFilter status;

  UnifiedWorkspaceFilters copyWith({
    String? search,
    AgreementFilter? agreement,
    DirectionFilter? direction,
    FundingFilter? funding,
    StatusFilter? status,
  }) => UnifiedWorkspaceFilters(
    search: search ?? this.search,
    agreement: agreement ?? this.agreement,
    direction: direction ?? this.direction,
    funding: funding ?? this.funding,
    status: status ?? this.status,
  );
}

class UnifiedAgreementSummary {
  const UnifiedAgreementSummary({
    required this.liabilityPrincipal,
    required this.receivablePrincipal,
    required this.dueSoonAmount,
    required this.dueSoonCount,
    required this.overdueAmount,
    required this.overdueCount,
  });
  final double liabilityPrincipal;
  final double receivablePrincipal;
  final double dueSoonAmount;
  final int dueSoonCount;
  final double overdueAmount;
  final int overdueCount;
}

UnifiedAgreementSummary summarizeUnifiedAgreements(
  Iterable<UnifiedFinanceAgreement> agreements,
) {
  var liability = 0.0, receivable = 0.0, dueSoon = 0.0, overdue = 0.0;
  var dueSoonCount = 0, overdueCount = 0;
  for (final agreement in agreements) {
    liability += agreement.liabilityPrincipal;
    receivable += agreement.receivablePrincipal;
    if (agreement.status == UnifiedAgreementStatus.dueSoon) {
      dueSoonCount++;
      dueSoon += agreement.installmentAmount ?? 0;
    }
    if (agreement.status == UnifiedAgreementStatus.overdue) {
      overdueCount++;
      overdue += agreement.installmentAmount ?? 0;
    }
  }
  return UnifiedAgreementSummary(
    liabilityPrincipal: liability,
    receivablePrincipal: receivable,
    dueSoonAmount: dueSoon,
    dueSoonCount: dueSoonCount,
    overdueAmount: overdue,
    overdueCount: overdueCount,
  );
}

List<UnifiedFinanceAgreement> filterUnifiedAgreements(
  Iterable<UnifiedFinanceAgreement> agreements,
  UnifiedWorkspaceFilters filters,
) {
  final query = filters.search.trim().toLowerCase();
  return agreements.where((agreement) {
    if (filters.agreement != AgreementFilter.all &&
        agreement.agreementKind.name != filters.agreement.name) {
      return false;
    }
    if (filters.direction != DirectionFilter.all &&
        agreement.direction.name != filters.direction.name) {
      return false;
    }
    if (filters.funding != FundingFilter.all &&
        agreement.fundingSource.name != filters.funding.name) {
      return false;
    }
    if (filters.status != StatusFilter.all &&
        agreement.status.name != filters.status.name) {
      return false;
    }
    if (query.isEmpty) return true;
    return [
      agreement.title,
      agreement.providerName,
      agreement.accountReference,
      agreement.personId,
      agreement.creditCardId,
      agreement.purchaseTransactionId,
    ].whereType<String>().any((value) => value.toLowerCase().contains(query));
  }).toList();
}

UnifiedWorkspaceState unifiedWorkspaceState(int totalCount, int visibleCount) =>
    totalCount == 0
    ? UnifiedWorkspaceState.empty
    : visibleCount == 0
    ? UnifiedWorkspaceState.noResults
    : UnifiedWorkspaceState.ready;

String statusLabel(UnifiedAgreementStatus status) => switch (status) {
  UnifiedAgreementStatus.active => 'Active',
  UnifiedAgreementStatus.dueSoon => 'Due soon',
  UnifiedAgreementStatus.overdue => 'Overdue',
  UnifiedAgreementStatus.defaulted => 'Defaulted',
  UnifiedAgreementStatus.closed => 'Closed',
};
String fundingLabel(UnifiedFundingSource funding) => switch (funding) {
  UnifiedFundingSource.bank => 'Bank',
  UnifiedFundingSource.financeCompany => 'Finance Company',
  UnifiedFundingSource.creditCard => 'Credit Card',
  UnifiedFundingSource.person => 'Person',
  UnifiedFundingSource.other => 'Other',
};

({
  String relationship,
  String remainingLabel,
  String? repaymentLabel,
  bool representedOnCard,
})
agreementCardPresentation(UnifiedFinanceAgreement agreement) => (
  relationship: agreement.direction == UnifiedAgreementDirection.lent
      ? 'Money I Lent'
      : agreement.agreementKind == UnifiedAgreementKind.installmentPurchase
      ? 'Installment Purchase · ${fundingLabel(agreement.fundingSource)}'
      : 'Money I Borrowed',
  remainingLabel: agreement.direction == UnifiedAgreementDirection.lent
      ? 'Principal owed to me'
      : 'Principal remaining',
  repaymentLabel: agreement.repaymentType == UnifiedRepaymentType.flexible
      ? 'Flexible'
      : agreement.repaymentType == UnifiedRepaymentType.oneTime
      ? 'One time'
      : null,
  representedOnCard:
      agreement.creditCardId != null &&
      agreement.cardOwnedLiability == 0 &&
      agreement.status != UnifiedAgreementStatus.closed,
);

String agreementDetailPath(UnifiedFinanceAgreement agreement) =>
    agreement.sourceType == UnifiedAgreementSourceType.loan
    ? '/loans/${agreement.sourceId}'
    : '/emis/${agreement.sourceId}';
