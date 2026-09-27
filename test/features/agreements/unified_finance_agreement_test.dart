import 'dart:convert';
import 'dart:io';

import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/agreements/domain/unified_finance_agreement.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 9, 25);

Installment installment(
  String scheduleId,
  double principal, {
  DateTime? due,
  double paid = 0,
}) => Installment(
  id: 'i',
  scheduleId: scheduleId,
  ownerType: OwnerType.loan,
  ownerId: 'owner',
  sequenceNumber: 1,
  dueDate: due ?? DateTime.utc(2026, 10, 10),
  amountDue: principal,
  amountPaid: paid,
  principalPortion: principal,
  interestPortion: 0,
  createdAt: now,
);
Loan loan({
  LoanDirection direction = LoanDirection.taken,
  LoanCategory category = LoanCategory.institutional,
  bool closed = false,
}) => Loan(
  id: 'loan-1',
  personId: category == LoanCategory.personal ? 'person-1' : null,
  direction: direction,
  category: category,
  institutionName: category == LoanCategory.institutional ? 'Bank' : null,
  loanAmount: 1000,
  loanDate: now,
  repaymentType: LoanRepaymentType.installment,
  installmentFrequency: ScheduleType.monthly,
  installmentCount: 1,
  scheduleId: 'schedule-loan',
  isClosed: closed,
  createdAt: now,
);
Emi emi({String? cardId, String? purchaseId, bool defaulted = false}) => Emi(
  id: 'emi-1',
  name: 'Purchase',
  principalAmount: 1000,
  startDate: now,
  installmentFrequency: ScheduleType.monthly,
  installmentCount: 1,
  endDate: now,
  scheduleId: 'schedule-emi',
  linkedCreditCardId: cardId,
  purchaseTransactionId: purchaseId,
  isDefaulted: defaulted,
  createdAt: now,
);
Transaction purchase({bool excluded = false}) => Transaction(
  id: 'purchase-1',
  type: TransactionType.expense,
  amount: 60000,
  dateTime: now,
  accountId: 'account-1',
  categoryId: 'cat',
  excludeFromCalculations: excluded,
  createdAt: now,
);

void main() {
  test(
    'loan mappings preserve bank, personal borrowed, lent and closed semantics',
    () {
      expect(
        loanToUnifiedAgreement(loan(), [
          installment('schedule-loan', 1000),
        ], now: now).fundingSource,
        UnifiedFundingSource.bank,
      );
      expect(
        loanToUnifiedAgreement(
          loan(category: LoanCategory.personal),
          [],
          now: now,
        ).direction,
        UnifiedAgreementDirection.borrowed,
      );
      expect(
        loanToUnifiedAgreement(
          loan(direction: LoanDirection.given, category: LoanCategory.personal),
          [],
          now: now,
        ).receivablePrincipal,
        1000,
      );
      expect(
        loanToUnifiedAgreement(loan(closed: true), [], now: now).status,
        UnifiedAgreementStatus.closed,
      );
    },
  );

  test('standard and defaulted EMI mappings are normalized', () {
    expect(
      emiToUnifiedAgreement(emi(), [
        installment('schedule-emi', 1000),
      ], now: now).nonCardEmiLiability,
      1000,
    );
    expect(
      emiToUnifiedAgreement(emi(defaulted: true), [], now: now).status,
      UnifiedAgreementStatus.defaulted,
    );
  });

  test('card EMI Cases A/B/C and legacy null preserve exact ownership', () {
    final caseA = emiToUnifiedAgreement(
      emi(cardId: 'card-1', purchaseId: 'purchase-1'),
      [installment('schedule-emi', 60000)],
      ownership: (cardAccountId: 'account-1', purchase: purchase()),
      now: now,
    );
    final caseB = emiToUnifiedAgreement(
      emi(cardId: 'card-1'),
      [installment('schedule-emi', 60000)],
      ownership: (cardAccountId: 'account-1', purchase: null),
      now: now,
    );
    final caseC = emiToUnifiedAgreement(
      emi(cardId: 'card-1', purchaseId: 'purchase-1'),
      [installment('schedule-emi', 60000)],
      ownership: (
        cardAccountId: 'account-1',
        purchase: purchase(excluded: true),
      ),
      now: now,
    );
    expect(caseA.liabilityPrincipal, 0);
    expect(60000 + caseA.liabilityPrincipal, 60000);
    expect(caseB.cardOwnedLiability, 60000);
    expect(caseC.cardOwnedLiability, 60000);
  });

  test('adapter is deterministic and leaves source objects unchanged', () {
    final source = loan();
    final before = source.loanAmount;
    final values = sortUnifiedAgreements([
      emiToUnifiedAgreement(emi(), [], now: now),
      loanToUnifiedAgreement(source, [], now: now),
    ]);
    expect(
      values.map((value) => '${value.sourceType.name}:${value.sourceId}'),
      ['emi:emi-1', 'loan:loan-1'],
    );
    expect(source.loanAmount, before);
  });

  test('matches the shared ten-scenario semantic fixture', () {
    final rows =
        (jsonDecode(
                  File(
                    'test/cross_platform_fixtures/unified_finance_agreement_fixture.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map<String, dynamic>>();
    final mapped = <UnifiedFinanceAgreement>[
      loanToUnifiedAgreement(loan(), [
        installment('schedule-loan', 1000, due: DateTime.utc(2026, 10, 1)),
      ], now: now),
      loanToUnifiedAgreement(loan(category: LoanCategory.personal), [
        installment('schedule-loan', 1000, due: DateTime.utc(2026, 10, 1)),
      ], now: now),
      loanToUnifiedAgreement(
        loan(direction: LoanDirection.given, category: LoanCategory.personal),
        [installment('schedule-loan', 1000, due: DateTime.utc(2026, 10, 1))],
        now: now,
      ),
      emiToUnifiedAgreement(emi(), [
        installment('schedule-emi', 1000),
      ], now: now),
      emiToUnifiedAgreement(
        emi(cardId: 'card-1', purchaseId: 'purchase-1'),
        [installment('schedule-emi', 1000)],
        ownership: (cardAccountId: 'account-1', purchase: purchase()),
        now: now,
      ),
      emiToUnifiedAgreement(
        emi(cardId: 'card-1'),
        [installment('schedule-emi', 1000)],
        ownership: (cardAccountId: 'account-1', purchase: null),
        now: now,
      ),
      emiToUnifiedAgreement(
        emi(cardId: 'card-1', purchaseId: 'purchase-1'),
        [installment('schedule-emi', 1000)],
        ownership: (
          cardAccountId: 'account-1',
          purchase: purchase(excluded: true),
        ),
        now: now,
      ),
      emiToUnifiedAgreement(
        emi(cardId: 'card-1'),
        [installment('schedule-emi', 1000)],
        ownership: (cardAccountId: 'account-1', purchase: null),
        now: now,
      ),
      loanToUnifiedAgreement(loan(closed: true), [
        installment('schedule-loan', 1000, due: DateTime.utc(2026, 10, 1)),
      ], now: now),
      emiToUnifiedAgreement(emi(defaulted: true), [
        installment('schedule-emi', 1000),
      ], now: now),
    ];
    for (var i = 0; i < rows.length; i++) {
      final value = mapped[i], row = rows[i];
      expect({
        'name': row['name'],
        'sourceType': value.sourceType.name,
        'direction': value.direction.name,
        'fundingSource': value.fundingSource.name,
        'status': value.status.name,
        'liabilityPrincipal': value.liabilityPrincipal,
        'receivablePrincipal': value.receivablePrincipal,
      }, row);
    }
  });
}
