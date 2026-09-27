// "Reverse & Delete" UI: swiping a wizard-created Loan whose origination money
// is still active opens the reversal confirmation (with the real Account
// effect) instead of the plain delete; confirming reverses it; a legacy Loan
// keeps the plain delete; the Trash screen never hard-deletes such a Loan; the
// dialog fits a small dark screen.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/data/firestore_crud_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/presentation/screens/loans_screen.dart';
import 'package:finance_app/features/lending/presentation/screens/loans_trash_screen.dart';
import 'package:finance_app/features/lending/presentation/widgets/reverse_origination_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'uid';

LoanRepository _loans(FakeFirebaseFirestore firestore) {
  final user = firestore.collection('users').doc(_uid);
  return LoanRepository(
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
}

Future<({FakeFirebaseFirestore firestore, Loan loan})> _seed({
  required bool moveMoney,
}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore
      .collection('users')
      .doc(_uid)
      .collection('accounts')
      .doc('hdfc')
      .set(
        Account(
          id: 'hdfc',
          name: 'HDFC',
          type: AccountType.bank,
          openingBalance: 100000,
          currentBalance: 100000,
          colorValue: 0,
          createdAt: DateTime(2026),
        ).toFirestore(),
      );
  final result = await _loans(firestore).createAgreementWithOrigination(
    idempotencyKey: 'ui-borrow-0001',
    name: 'Renovation',
    category: LoanCategory.institutional,
    institutionName: 'HDFC Bank',
    fundingSource: LoanFundingSource.bank,
    direction: LoanDirection.taken,
    loanAmount: 50000,
    loanDate: DateTime(2026, 1, 10),
    repaymentType: LoanRepaymentType.installment,
    installmentFrequency: ScheduleType.monthly,
    installmentCount: 12,
    movementAccountId: moveMoney ? 'hdfc' : null,
  );
  return (firestore: firestore, loan: result.loan);
}

Widget _app(FakeFirebaseFirestore firestore, Widget home, {ThemeData? theme}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUserIdProvider.overrideWithValue(_uid),
      ],
      child: MaterialApp(theme: theme ?? AppTheme.light, home: home),
    );

Future<double> _balance(FakeFirebaseFirestore firestore) async =>
    ((await firestore
                    .collection('users')
                    .doc(_uid)
                    .collection('accounts')
                    .doc('hdfc')
                    .get())
                .data()!['currentBalance']
            as num)
        .toDouble();

const _borrowedCopy =
    'This will remove the original ₹50,000 received into HDFC and reverse the loan creation.';

void main() {
  testWidgets(
    'swipe on an originated Loan with active money → Reverse & Delete '
    'confirmation; Cancel changes nothing; confirm reverses it',
    (tester) async {
      final seeded = await _seed(moveMoney: true);
      await tester.pumpWidget(_app(seeded.firestore, const LoansScreen()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Reverse & Delete Renovation?'), findsOneWidget);
      expect(find.text(_borrowedCopy), findsOneWidget);
      expect(find.text('Delete Loan?'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await _balance(seeded.firestore), 150000);
      expect(find.byType(Dismissible), findsOneWidget);

      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reverse & Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Loan creation reversed'), findsOneWidget);
      expect(await _balance(seeded.firestore), 100000);
      final loan = await _loans(seeded.firestore).getByKey(seeded.loan.id);
      expect(loan!.isDeleted, isTrue);
    },
  );

  testWidgets('an originated Loan without money keeps the plain delete', (
    tester,
  ) async {
    final seeded = await _seed(moveMoney: false);
    await tester.pumpWidget(_app(seeded.firestore, const LoansScreen()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reverse & Delete'), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Trash: "Delete forever" on a Loan trashed with active money '
      'offers the reversal instead', (tester) async {
    final seeded = await _seed(moveMoney: true);
    // State an older app could leave behind: trashed with the money active.
    await FirestoreCrudRepository<Loan>(
      _loans(seeded.firestore).collection,
    ).softDelete(seeded.loan);
    await tester.pumpWidget(_app(seeded.firestore, const LoansTrashScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete forever'));
    await tester.pumpAndSettle();
    expect(find.text(_borrowedCopy), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse & Delete'));
    await tester.pumpAndSettle();
    expect(await _balance(seeded.firestore), 100000);
    expect(
      await _loans(seeded.firestore).getByKey(seeded.loan.id),
      isNotNull,
      reason: 'reversed, not hard-deleted',
    );
  });

  testWidgets('confirmation fits a small dark screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmReverseOrigination(
              context,
              loanName: 'A rather long home renovation loan name',
              message: _borrowedCopy,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(_borrowedCopy), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text(_borrowedCopy))).brightness,
      Brightness.dark,
    );
  });
}
