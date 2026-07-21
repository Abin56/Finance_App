import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/expense_participant.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/expense/presentation/screens/share_expense_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _expense({required List<ExpenseParticipant> participants}) {
  return Expense(
    id: 'exp1',
    description: 'Dinner at BBQ Nation',
    totalAmount: 3000,
    date: DateTime(2026, 7, 2),
    categoryId: 'cat1',
    accountId: 'acc1',
    transactionId: 'txn1',
    splitType: SplitType.equal,
    participants: participants,
    scheduleId: 'sched1',
    createdAt: DateTime(2026, 7, 2),
  );
}

Installment _installment({required String id, double amountDue = 1000, double amountPaid = 0}) {
  return Installment(
    id: id,
    scheduleId: 'sched1',
    ownerType: OwnerType.splitExpense,
    ownerId: 'exp1',
    sequenceNumber: 1,
    dueDate: DateTime(2026, 7, 2),
    amountDue: amountDue,
    amountPaid: amountPaid,
    createdAt: DateTime(2026, 7, 2),
  );
}

void main() {
  testWidgets('preview shows receipt details, participant statuses, and export actions', (tester) async {
    final rahul = ExpenseParticipant(name: 'Rahul', share: 1000, personId: 'p-rahul', installmentId: 'inst-rahul');
    final arjun = ExpenseParticipant(name: 'Arjun', share: 1000, personId: 'p-arjun', installmentId: 'inst-arjun');
    final me = ExpenseParticipant(name: 'Me', share: 1000, isMe: true);
    final expense = _expense(participants: [rahul, arjun, me]);
    final installments = [
      _installment(id: 'inst-rahul', amountPaid: 1000),
      _installment(id: 'inst-arjun', amountPaid: 500),
    ];

    await tester.pumpWidget(
      MaterialApp(home: ShareExpensePreviewScreen(expense: expense, installments: installments)),
    );

    expect(find.text('Share Expense'), findsOneWidget);
    expect(find.text('Dinner at BBQ Nation'), findsOneWidget);
    expect(find.text('₹3,000.00'), findsNWidgets(2)); // hero amount + totals row
    expect(find.text('₹1,500.00'), findsNWidgets(2)); // collected tile + totals row

    expect(find.text('Rahul'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget); // Rahul settled in full
    expect(find.text('Partial'), findsOneWidget); // Arjun paid 500 of 1000
    expect(find.text('Payer'), findsOneWidget); // Me

    expect(find.text('Share Receipt'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
  });
}
