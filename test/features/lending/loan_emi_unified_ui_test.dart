// Unified Loan & EMI section (web parity): first run explains Loan vs EMI;
// Add → Loan / EMI chooser; Add EMI's "It's on a credit card" is off by
// default, lists only open cards once on, and saves the card link as a
// credit-card EMI; an account-linked Loan keeps its institutional metadata.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_status.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/screens/loan_emi_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'uid';

Future<void> _seedAccount(
  FakeFirebaseFirestore firestore,
  String id,
  String name,
  AccountType type,
) => firestore
    .collection('users')
    .doc(_uid)
    .collection('accounts')
    .doc(id)
    .set(
      Account(
        id: id,
        name: name,
        type: type,
        openingBalance: 0,
        currentBalance: 0,
        colorValue: 0,
        createdAt: DateTime(2026),
      ).toFirestore(),
    );

Future<void> _seedCard(
  FakeFirebaseFirestore firestore,
  String id,
  String accountId,
  CreditCardStatus status,
) => firestore
    .collection('users')
    .doc(_uid)
    .collection('creditCards')
    .doc(id)
    .set(
      CreditCardProfile(
        id: id,
        accountId: accountId,
        statementDay: 5,
        paymentDueDay: 25,
        creditLimit: 80000,
        createdAt: DateTime(2026),
        status: status,
      ).toFirestore(),
    );

Future<FakeFirebaseFirestore> _seed() async {
  final firestore = FakeFirebaseFirestore();
  await _seedAccount(firestore, 'visa-acc', 'Visa Card', AccountType.card);
  await _seedAccount(firestore, 'old-acc', 'Old Card', AccountType.card);
  await _seedCard(firestore, 'visa', 'visa-acc', CreditCardStatus.active);
  await _seedCard(firestore, 'old', 'old-acc', CreditCardStatus.closed);
  return firestore;
}

Widget _app(FakeFirebaseFirestore firestore) => ProviderScope(
  overrides: [
    firestoreProvider.overrideWithValue(firestore),
    currentUserIdProvider.overrideWithValue(_uid),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const LoanEmiScreen()),
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first run explains Loan vs EMI and opens the picked form', (
    tester,
  ) async {
    await tester.pumpWidget(_app(await _seed()));
    await tester.pumpAndSettle();

    expect(find.text('Loan & EMI').hitTestable(), findsOneWidget);
    expect(find.text('Track what you owe in one place'), findsOneWidget);

    await tester.tap(find.text('Loan'));
    await tester.pumpAndSettle();
    expect(find.text('Add a Loan'), findsWidgets);
    // A Loan defaults to money borrowed from a bank / lender.
    expect(find.text('Loan taken from'), findsOneWidget);
    // Account movement is opt-in; card accounts are never offered, so with
    // only cards the form points to Accounts instead of an inline create.
    expect(find.text('Go to Accounts'), findsNothing);
    await _tapVisible(tester, find.text('Money came into one of my accounts'));
    expect(find.text('Go to Accounts'), findsOneWidget);
  });

  testWidgets('Add asks Loan or EMI first', (tester) async {
    LoanEmiTab? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await LoanEmiAddChooser.show(context),
            child: const Text('Add'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('What are you adding?'), findsOneWidget);
    expect(find.text('Loan'), findsOneWidget);
    expect(find.text('EMI'), findsOneWidget);

    await tester.tap(find.text('EMI'));
    await tester.pumpAndSettle();
    expect(picked, LoanEmiTab.emis);
  });

  testWidgets(
    'Add EMI: card link off by default; on → open cards only; saves as a '
    'credit-card EMI on that card',
    (tester) async {
      final firestore = await _seed();
      await tester.pumpWidget(_app(firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.text('EMI'));
      await tester.pumpAndSettle();

      expect(find.text("It's on a credit card"), findsOneWidget);
      expect(find.text('Select a card'), findsNothing);
      expect(find.text('Loan on card'), findsNothing);

      await _tapVisible(tester, find.text("It's on a credit card"));
      expect(find.text('Select a card'), findsOneWidget);
      expect(find.text('Purchase on EMI'), findsOneWidget);

      await _tapVisible(tester, find.text('Select a card'));
      expect(find.text('Visa Card').hitTestable(), findsOneWidget);
      expect(find.text('Old Card'), findsNothing);
      await tester.tap(find.text('Visa Card').hitTestable());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, "What's this EMI for?"),
        'iPhone 16',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount on EMI'),
        '40000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Installments'),
        '12',
      );
      await _tapVisible(tester, find.text('Add EMI').last);

      final emis = await firestore
          .collection('users')
          .doc(_uid)
          .collection('emis')
          .get();
      expect(emis.docs, hasLength(1));
      final data = emis.docs.single.data();
      expect(data['name'], 'iPhone 16');
      expect(data['principalAmount'], 40000);
      expect(data['linkedCreditCardId'], 'visa');
      expect(data['loanType'], 'creditCard');
      expect(data['purchaseTransactionId'], isNull);
    },
  );

  test('account-linked Loan keeps its institutional details', () async {
    final firestore = FakeFirebaseFirestore();
    await _seedAccount(firestore, 'hdfc', 'HDFC', AccountType.bank);
    final user = firestore.collection('users').doc(_uid);
    final repository = LoanRepository(
      user
          .collection('loans')
          .withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          ),
      PaymentScheduleRepository(
        user
            .collection('paymentSchedules')
            .withConverter<PaymentSchedule>(
              fromFirestore: PaymentSchedule.fromFirestore,
              toFirestore: (s, _) => s.toFirestore(),
            ),
      ),
      (scheduleId) => InstallmentRepository(
        user
            .collection('paymentSchedules')
            .doc(scheduleId)
            .collection('installments')
            .withConverter<Installment>(
              fromFirestore: Installment.fromFirestore,
              toFirestore: (i, _) => i.toFirestore(),
            ),
      ),
    );

    final result = await repository.createAgreementWithOrigination(
      idempotencyKey: 'form-loan-0001',
      movementAccountId: 'hdfc',
      category: LoanCategory.institutional,
      institutionName: 'HDFC Bank',
      loanType: 'Vehicle Loan',
      accountNumber: '1234',
      branch: 'MG Road',
      payerPersonId: 'dad',
      direction: LoanDirection.taken,
      loanAmount: 100000,
      loanDate: DateTime(2026, 1, 10),
      repaymentType: LoanRepaymentType.installment,
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
    );

    final saved = (await user.collection('loans').doc(result.loan.id).get())
        .data()!;
    expect(saved['loanType'], 'Vehicle Loan');
    expect(saved['accountNumber'], '1234');
    expect(saved['branch'], 'MG Road');
    expect(saved['payerPersonId'], 'dad');
    expect(result.transactionId, isNotNull);
  });
}
