import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/expense_participant.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/people/presentation/providers/person_timeline_providers.dart';
import 'package:finance_app/features/people/presentation/screens/person_statement_screen.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';

/// 360x640 is the standard small Android phone (same baseline as
/// account_detail_screen_small_layout_test.dart). The new Previous Cycle
/// Pending / Current Cycle section headers plus the "carried forward"
/// highlighted tile (a warning-tinted left border, an extra label row, the
/// amount, status pill, and direction text all in the same row/column) are
/// the parts most at risk of overflowing on a narrow phone.
const _smallPhone = Size(360, 640);

void main() {
  // Anchored to the real "now" the provider itself uses (CycleAnchor.classify
  // defaults to DateTime.now()), so these dates land in previous/current
  // cycle regardless of which day this test happens to run on.
  const anchor = personCycleAnchor;
  final previousCycle = anchor.previousCycleFor();
  final currentCycle = anchor.currentCycleFor();
  final previousCycleDate = previousCycle.start.add(const Duration(days: 1));
  final currentCycleDate = currentCycle.start.add(const Duration(days: 1));

  testWidgets('Previous Cycle Pending + Current Cycle sections fit a small phone without overflow', (tester) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final person = Person(
      id: 'p1',
      name: 'A Very Long Test Contact Name',
      openingBalance: 0,
      currentBalance: 1234567.89,
      avatarColorValue: 0xFF000000,
      createdAt: DateTime(2026, 1, 1),
    );

    // Previous-cycle entry, still Pending -> must carry forward.
    final pendingLedgerEntry = LedgerEntry(
      id: 'l-pending',
      personId: 'p1',
      type: LedgerEntryType.gave,
      amount: 987654.32,
      date: previousCycleDate,
      note: 'Split: A Very Long Restaurant Name For This Expense',
      transactionRef: 'txn-pending',
      createdAt: previousCycleDate,
    );
    final pendingExpense = Expense(
      id: 'exp-pending',
      description: 'A Very Long Restaurant Name For This Expense',
      totalAmount: 987654.32,
      date: previousCycleDate,
      categoryId: 'c1',
      accountId: 'a1',
      transactionId: 'txn-pending',
      splitType: SplitType.custom,
      participants: [
        ExpenseParticipant(personId: 'p1', name: person.name, share: 987654.32, installmentId: 'inst-pending'),
      ],
      createdAt: previousCycleDate,
      scheduleId: 'sched-pending',
    );
    final pendingInstallment = Installment(
      id: 'inst-pending',
      scheduleId: 'sched-pending',
      ownerType: OwnerType.splitExpense,
      ownerId: 'exp-pending',
      sequenceNumber: 1,
      dueDate: previousCycleDate.add(const Duration(days: 7)),
      amountDue: 987654.32,
      createdAt: previousCycleDate,
    );

    // Current-cycle entry, fully settled -> still always shown.
    final settledLedgerEntry = LedgerEntry(
      id: 'l-settled',
      personId: 'p1',
      type: LedgerEntryType.gave,
      amount: 500,
      date: currentCycleDate,
      note: 'Split: Movie tickets',
      transactionRef: 'txn-settled',
      createdAt: currentCycleDate,
    );
    final settledExpense = Expense(
      id: 'exp-settled',
      description: 'Movie tickets',
      totalAmount: 500,
      date: currentCycleDate,
      categoryId: 'c1',
      accountId: 'a1',
      transactionId: 'txn-settled',
      splitType: SplitType.custom,
      participants: [
        ExpenseParticipant(personId: 'p1', name: person.name, share: 500, installmentId: 'inst-settled'),
      ],
      createdAt: currentCycleDate,
      scheduleId: 'sched-settled',
    );
    final settledInstallment = Installment(
      id: 'inst-settled',
      scheduleId: 'sched-settled',
      ownerType: OwnerType.splitExpense,
      ownerId: 'exp-settled',
      sequenceNumber: 1,
      dueDate: currentCycleDate.add(const Duration(days: 7)),
      amountDue: 500,
      amountPaid: 500,
      createdAt: currentCycleDate,
    );

    // A reference-only transaction (person picked, "owes me" left off) — the
    // "Recharge vi" bug-report scenario: shows its real amount but must never
    // affect balance/stats, flagged with the reference-only pill.
    final referenceTransaction = Transaction(
      id: 'txn-reference',
      type: TransactionType.expense,
      amount: 470,
      dateTime: currentCycleDate,
      accountId: 'a1',
      categoryId: 'c1',
      description: 'A Very Long Recharge Description Here',
      linkedPersonId: 'p1',
      createdAt: currentCycleDate,
    );

    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        peopleStreamProvider.overrideWith((ref) => Stream.value([person])),
        ledgerStreamProvider('p1').overrideWith((ref) => Stream.value([pendingLedgerEntry, settledLedgerEntry])),
        ledgerTrashStreamProvider('p1').overrideWith((ref) => Stream.value(const [])),
        expensesStreamProvider.overrideWith((ref) => Stream.value([pendingExpense, settledExpense])),
        installmentsStreamProvider('sched-pending').overrideWith((ref) => Stream.value([pendingInstallment])),
        installmentsStreamProvider('sched-settled').overrideWith((ref) => Stream.value([settledInstallment])),
        loansForPersonProvider('p1').overrideWithValue(const []),
        transactionsStreamProvider.overrideWith((ref) => Stream.value([referenceTransaction])),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonStatementScreen(personId: 'p1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Previous Cycle Pending'), findsOneWidget);
    expect(find.text('Current Cycle'), findsOneWidget);
    expect(find.textContaining('CARRIED FORWARD'), findsOneWidget);

    // The reference-only entry's pill is further down the current-cycle
    // list, past the two expense entries above — scroll to bring it into
    // the sliver's built extent before asserting on it.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Reference only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Previous Cycle section is hidden once its only entry is fully settled', (tester) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final person = Person(
      id: 'p1',
      name: 'Test Contact',
      openingBalance: 0,
      currentBalance: 0,
      avatarColorValue: 0xFF000000,
      createdAt: DateTime(2026, 1, 1),
    );

    final settledLedgerEntry = LedgerEntry(
      id: 'l-settled',
      personId: 'p1',
      type: LedgerEntryType.gave,
      amount: 500,
      date: previousCycleDate,
      note: 'Split: Lunch',
      transactionRef: 'txn-settled',
      createdAt: previousCycleDate,
    );
    final settledExpense = Expense(
      id: 'exp-settled',
      description: 'Lunch',
      totalAmount: 500,
      date: previousCycleDate,
      categoryId: 'c1',
      accountId: 'a1',
      transactionId: 'txn-settled',
      splitType: SplitType.custom,
      participants: [
        ExpenseParticipant(personId: 'p1', name: person.name, share: 500, installmentId: 'inst-settled'),
      ],
      createdAt: previousCycleDate,
      scheduleId: 'sched-settled',
    );
    final settledInstallment = Installment(
      id: 'inst-settled',
      scheduleId: 'sched-settled',
      ownerType: OwnerType.splitExpense,
      ownerId: 'exp-settled',
      sequenceNumber: 1,
      dueDate: previousCycleDate.add(const Duration(days: 7)),
      amountDue: 500,
      amountPaid: 500,
      createdAt: previousCycleDate,
    );

    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        peopleStreamProvider.overrideWith((ref) => Stream.value([person])),
        ledgerStreamProvider('p1').overrideWith((ref) => Stream.value([settledLedgerEntry])),
        ledgerTrashStreamProvider('p1').overrideWith((ref) => Stream.value(const [])),
        expensesStreamProvider.overrideWith((ref) => Stream.value([settledExpense])),
        installmentsStreamProvider('sched-settled').overrideWith((ref) => Stream.value([settledInstallment])),
        loansForPersonProvider('p1').overrideWithValue(const []),
        transactionsStreamProvider.overrideWith((ref) => Stream.value(const <Transaction>[])),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonStatementScreen(personId: 'p1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Previous Cycle Pending'), findsNothing);
    expect(find.text('Current Cycle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
