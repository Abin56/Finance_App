import 'package:finance_app/features/agreements/domain/unified_finance_agreement.dart';
import 'package:finance_app/features/agreements/domain/unified_workspace_model.dart';
import 'package:flutter_test/flutter_test.dart';

UnifiedFinanceAgreement agreement({
  String id = 'loan-1',
  String title = 'SBI Personal Loan',
  UnifiedAgreementSourceType source = UnifiedAgreementSourceType.loan,
  UnifiedAgreementKind kind = UnifiedAgreementKind.loan,
  UnifiedAgreementDirection direction = UnifiedAgreementDirection.borrowed,
  UnifiedFundingSource funding = UnifiedFundingSource.bank,
  UnifiedAgreementStatus status = UnifiedAgreementStatus.active,
  double liability = 800,
  double receivable = 0,
  double cardOwned = 0,
  String? cardId,
}) => UnifiedFinanceAgreement(
  sourceType: source,
  sourceId: id,
  agreementKind: kind,
  direction: direction,
  repaymentType: UnifiedRepaymentType.scheduled,
  fundingSource: funding,
  personId: direction == UnifiedAgreementDirection.lent ? 'rahul' : null,
  creditCardId: cardId,
  purchaseTransactionId: null,
  linkedAccountId: null,
  accountReference: 'AC-42',
  title: title,
  providerName: funding == UnifiedFundingSource.bank ? 'SBI' : 'Provider',
  purchaseAmount: null,
  downPayment: null,
  originalPrincipal: 1000,
  remainingPrincipal: 800,
  liabilityPrincipal: liability,
  receivablePrincipal: receivable,
  cardOwnedLiability: cardOwned,
  nonCardEmiLiability: liability - cardOwned,
  paidPrincipal: 200,
  paidInterest: 10,
  futureInterest: 90,
  interestRate: 8,
  interestType: 'flat',
  repaymentFrequency: null,
  installmentCount: 10,
  installmentAmount: 100,
  nextDueDate: DateTime(2026, 10, 5),
  status: status,
  sourceStatus: status.name,
  scheduleId: 'schedule-$id',
  createdAt: DateTime(2026),
);

void main() {
  final loan = agreement();
  final lent = agreement(
    id: 'lent-1',
    title: 'Rahul Personal Loan',
    direction: UnifiedAgreementDirection.lent,
    funding: UnifiedFundingSource.person,
    liability: 0,
    receivable: 800,
  );
  final emi = agreement(
    id: 'emi-1',
    title: 'Phone',
    source: UnifiedAgreementSourceType.emi,
    kind: UnifiedAgreementKind.installmentPurchase,
    funding: UnifiedFundingSource.financeCompany,
  );

  test('1 Loan appears in unified list', () {
    expect(filterUnifiedAgreements([loan], const UnifiedWorkspaceFilters()), [
      loan,
    ]);
  });
  test('2 EMI appears in unified list', () {
    expect(filterUnifiedAgreements([emi], const UnifiedWorkspaceFilters()), [
      emi,
    ]);
  });
  test('3 borrowed Loan presentation', () {
    expect(agreementCardPresentation(loan).relationship, 'Loan I Took');
  });
  test('4 lent Loan presentation', () {
    expect(agreementCardPresentation(lent).relationship, 'Loan I Gave');
  });
  test('5 standard EMI presentation', () {
    expect(
      agreementCardPresentation(emi).relationship,
      contains('Installment Purchase'),
    );
  });
  test('6 card-linked EMI presentation remains visible', () {
    final cardEmi = agreement(
      source: UnifiedAgreementSourceType.emi,
      kind: UnifiedAgreementKind.installmentPurchase,
      funding: UnifiedFundingSource.creditCard,
      cardId: 'card-1',
      liability: 0,
    );
    expect(agreementCardPresentation(cardEmi).representedOnCard, isTrue);
  });
  test('7 card-owned EMI does not inflate summary liability', () {
    final represented = agreement(
      source: UnifiedAgreementSourceType.emi,
      kind: UnifiedAgreementKind.installmentPurchase,
      funding: UnifiedFundingSource.creditCard,
      cardId: 'card-1',
      liability: 0,
    );
    expect(
      summarizeUnifiedAgreements([loan, represented]).liabilityPrincipal,
      800,
    );
  });
  test('8 search normalized fields', () {
    expect(
      filterUnifiedAgreements([
        loan,
        lent,
      ], const UnifiedWorkspaceFilters(search: 'rahul')),
      [lent],
    );
  });
  test('9 agreement filter', () {
    expect(
      filterUnifiedAgreements(
        [loan, emi],
        const UnifiedWorkspaceFilters(
          agreement: AgreementFilter.installmentPurchase,
        ),
      ),
      [emi],
    );
  });
  test('10 direction filter', () {
    expect(
      filterUnifiedAgreements([
        loan,
        lent,
      ], const UnifiedWorkspaceFilters(direction: DirectionFilter.lent)),
      [lent],
    );
  });
  test('11 funding filter', () {
    expect(
      filterUnifiedAgreements([
        loan,
        emi,
      ], const UnifiedWorkspaceFilters(funding: FundingFilter.financeCompany)),
      [emi],
    );
  });
  test('12 status filter', () {
    final overdue = agreement(status: UnifiedAgreementStatus.overdue);
    expect(
      filterUnifiedAgreements([
        loan,
        overdue,
      ], const UnifiedWorkspaceFilters(status: StatusFilter.overdue)),
      [overdue],
    );
  });
  test('13 closed Loan stays filterable', () {
    final closed = agreement(status: UnifiedAgreementStatus.closed);
    expect(
      filterUnifiedAgreements([
        closed,
      ], const UnifiedWorkspaceFilters(status: StatusFilter.closed)),
      [closed],
    );
  });
  test('14 defaulted EMI stays filterable', () {
    final value = agreement(
      source: UnifiedAgreementSourceType.emi,
      kind: UnifiedAgreementKind.installmentPurchase,
      status: UnifiedAgreementStatus.defaulted,
    );
    expect(
      filterUnifiedAgreements([
        value,
      ], const UnifiedWorkspaceFilters(status: StatusFilter.defaulted)),
      [value],
    );
  });
  test('15 empty state', () {
    expect(unifiedWorkspaceState(0, 0), UnifiedWorkspaceState.empty);
  });
  test('16 no-results state', () {
    expect(unifiedWorkspaceState(2, 0), UnifiedWorkspaceState.noResults);
  });
  test('17 live Loan replacement recomputes totals', () {
    expect(
      summarizeUnifiedAgreements([
        agreement(liability: 300),
      ]).liabilityPrincipal,
      300,
    );
  });
  test('18 live EMI replacement recomputes totals', () {
    expect(
      summarizeUnifiedAgreements([
        agreement(
          source: UnifiedAgreementSourceType.emi,
          kind: UnifiedAgreementKind.installmentPurchase,
          liability: 125,
        ),
      ]).liabilityPrincipal,
      125,
    );
  });
  test('19 correct Loan detail navigation', () {
    expect(agreementDetailPath(loan), '/loans/loan-1');
  });
  test('19 correct EMI detail navigation', () {
    expect(agreementDetailPath(emi), '/emis/emi-1');
  });
}
