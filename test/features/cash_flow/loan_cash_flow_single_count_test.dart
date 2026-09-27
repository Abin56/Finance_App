import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/date_range_strategy.dart';
import 'package:finance_app/core/dashboard/domain/financial_view_module.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/dashboard/presentation/providers/expense_calculator_provider.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_period.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 1 / A+B — a Loan payment's money movement is counted exactly once
/// by Cash Flow and by the dashboard financial views, with the sign given by
/// the Loan's direction:
///  - modern payments (`LoanAdvancePaymentRepository.record`) post ONE
///    Transaction and stamp its id on every InstallmentPayment → counted via
///    the Transaction only;
///  - legacy payments (no `transactionId`) → counted from the schedule.
void main() {
  late ProviderContainer container;
  final day = DateTime(2026, 9, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    container.read(cashFlowDateRangeProvider.notifier).state = CashFlowPeriod.custom(
      DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30, 23, 59, 59, 999)),
    );
  });

  Future<String> account() async => (await container
          .read(accountRepositoryProvider)
          .createAccount(name: 'Bank', type: AccountType.bank, openingBalance: 100000, colorValue: 0xFF000000))
      .id;

  Future<(Loan, List<Installment>)> loan(LoanDirection direction, {int count = 4}) async {
    final loan = await container.read(loanRepositoryProvider).createLoan(
          loanAmount: 4000,
          loanDate: DateTime(2026, 8, 15),
          repaymentType: LoanRepaymentType.installment,
          direction: direction,
          category: LoanCategory.institutional,
          institutionName: 'Bank',
          installmentFrequency: ScheduleType.monthly,
          installmentCount: count,
        );
    await container.read(loansStreamProvider.future);
    final sub = container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
    addTearDown(sub.close);
    final installments = await container.read(installmentsStreamProvider(loan.scheduleId).future);
    return (loan, [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber)));
  }


  /// Keeps every stream the cash-flow providers watch alive and settled.
  Future<void> settle(Loan loan) async {
    final sub = container.listen(installmentsStreamProvider(loan.scheduleId), (_, _) {});
    addTearDown(sub.close);
    final installments = await container.read(installmentsStreamProvider(loan.scheduleId).future);
    for (final i in installments) {
      final key = (scheduleId: loan.scheduleId, installmentId: i.id);
      final s = container.listen(installmentPaymentsStreamProvider(key), (_, _) {});
      addTearDown(s.close);
      await container.read(installmentPaymentsStreamProvider(key).future);
    }
    final t = container.listen(transactionsStreamProvider, (_, _) {});
    addTearDown(t.close);
    await container.read(transactionsStreamProvider.future);
  }

  double moneyOut() => container.read(cashFlowForRangeProvider).moneyOut;
  double moneyIn() => container.read(cashFlowForRangeProvider).moneyIn;

  double dashboardSpent() => container
      .read(
        financialViewResultProvider(
          WidgetConfiguration(
            id: 'spent',
            type: DashboardWidgetType.financialView,
            title: 'Spent',
            // Bucketed by installment DUE date (first one = the loan date, 15 Aug).
            dateStrategy: CustomDateRange(DateTime(2026, 8, 1), DateTime(2026, 10, 31, 23, 59, 59)),
            financialViewModule: FinancialViewModule.combinedExpenses,
          ),
        ),
      )
      .amount;

  test('modern linked EMI payment (borrowed) is counted once in Cash Flow and in the dashboard', () async {
    final acct = await account();
    final (l, installments) = await loan(LoanDirection.taken);
    await container.read(loanAdvancePaymentRepositoryProvider).record(
          loan: l, scheduleInstallments: installments, accountId: acct,
          amount: 1000, date: day, idempotencyKey: 'modern-1');
    await settle(l);
    expect(moneyOut(), 1000, reason: 'Transaction + schedule used to make this 2000');
    expect(dashboardSpent(), 1000);
  });

  test('legacy unlinked payment (no Transaction) is still counted from the schedule', () async {
    final (l, installments) = await loan(LoanDirection.taken);
    final key = (scheduleId: l.scheduleId, installmentId: installments.first.id);
    await container.read(installmentPaymentRepositoryProvider(key)).recordPayment(installments.first, amount: 1000, date: day);
    await settle(l);
    expect(moneyOut(), 1000);
    expect(dashboardSpent(), 1000);
  });

  test('partial modern payment is counted once, at the partial amount', () async {
    final acct = await account();
    final (l, installments) = await loan(LoanDirection.taken);
    await container.read(loanAdvancePaymentRepositoryProvider).record(
          loan: l, scheduleInstallments: installments, accountId: acct,
          amount: 400, date: day, idempotencyKey: 'partial-1');
    await settle(l);
    expect(moneyOut(), 400);
  });

  test('one physical payment spread over several installments is counted once', () async {
    final acct = await account();
    final (l, installments) = await loan(LoanDirection.taken);
    final result = await container.read(loanAdvancePaymentRepositoryProvider).record(
          loan: l, scheduleInstallments: installments, accountId: acct,
          amount: 3000, date: day, includeUpcomingInstallments: true, idempotencyKey: 'multi-1');
    expect(result.paymentIds, hasLength(3));
    await settle(l);
    expect(moneyOut(), 3000, reason: 'not 3000 (Transaction) + 3000 (three schedule lines)');
  });

  test('reversal removes the movement entirely', () async {
    final acct = await account();
    final (l, installments) = await loan(LoanDirection.taken);
    final result = await container.read(loanAdvancePaymentRepositoryProvider).record(
          loan: l, scheduleInstallments: installments, accountId: acct,
          amount: 1000, date: day, idempotencyKey: 'rev-1');
    await container.read(loanAdvancePaymentRepositoryProvider).reversePayment(
          loan: l, transactionId: result.transactionId, paymentIds: result.paymentIds,
          installmentIds: result.installmentIds, reversalIdempotencyKey: 'rev-1-undo');
    await settle(l);
    expect(moneyOut(), 0);
    expect(dashboardSpent(), 0);
  });

  test('lent loan: a modern repayment received is Money In once, and never dashboard spending', () async {
    final acct = await account();
    final (l, installments) = await loan(LoanDirection.given);
    await container.read(loanAdvancePaymentRepositoryProvider).record(
          loan: l, scheduleInstallments: installments, accountId: acct,
          amount: 1000, date: day, idempotencyKey: 'lent-1');
    await settle(l);
    expect(moneyIn(), 1000);
    expect(moneyOut(), 0);
    expect(dashboardSpent(), 0);
  });

  test('lent loan: a legacy unlinked repayment is Money In and not dashboard spending', () async {
    final (l, installments) = await loan(LoanDirection.given);
    final key = (scheduleId: l.scheduleId, installmentId: installments.first.id);
    await container.read(installmentPaymentRepositoryProvider(key)).recordPayment(installments.first, amount: 1000, date: day);
    await settle(l);
    expect(moneyIn(), 1000);
    expect(dashboardSpent(), 0, reason: 'used to be counted as spending regardless of direction');
  });
}

