import 'package:finance_app/core/dashboard/presentation/providers/upcoming_due_breakdown_provider.dart';
import 'package:finance_app/core/dashboard/presentation/providers/upcoming_due_provider.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/upcoming_due_breakdown_sheet.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/upcoming_payments_widget_card.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [UpcomingDueRow]'s redesigned transaction-style layout (44px tinted
/// icon, title, due label, status badge, prominent trailing amount,
/// chevron) plus [UpcomingDueBreakdownSheet]'s per-kind ownership summary,
/// checked on a small (360dp) phone — the row now packs more into the same
/// horizontal space (a badge row it didn't show inline before, a larger
/// icon, a chevron) so this is the one place that combination is exercised
/// with realistic long titles/large amounts.
const _smallPhone = Size(360, 640);
const _scales = [1.0, 1.3, 2.0];

void main() {
  final now = DateTime.now();

  final creditCardItem = (
    kind: UpcomingDueKind.creditCard,
    title: 'A Fairly Long Card Name •••• 4321',
    dueDate: now.subtract(const Duration(days: 20)),
    remaining: 1234567.89,
    urgency: PaymentUrgency.carriedForward,
    isCarriedOver: true,
    routeId: 'card1',
    secondaryRouteId: 'stmt1',
  );

  final billItem = (
    kind: UpcomingDueKind.bill,
    title: 'Electricity',
    dueDate: now.add(const Duration(days: 3)),
    remaining: 2350.0,
    urgency: PaymentUrgency.dueSoon,
    isCarriedOver: false,
    routeId: 'bill1',
    secondaryRouteId: null,
  );

  Future<void> pumpAt(WidgetTester tester, double scale, Widget child, {List<Override>? overrides}) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides ?? const [],
        child: MaterialApp(
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: inner!,
          ),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in _scales) {
    testWidgets('UpcomingDueRow renders carried-over and normal items without overflow @${scale}x', (tester) async {
      await pumpAt(
        tester,
        scale,
        Column(children: [UpcomingDueRow(item: creditCardItem), UpcomingDueRow(item: billItem)]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Carried Forward'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    });
  }

  for (final scale in _scales) {
    testWidgets('UpcomingDueBreakdownSheet renders a Credit Card breakdown without overflow @${scale}x',
        (tester) async {
      await pumpAt(
        tester,
        scale,
        UpcomingDueBreakdownSheet(item: creditCardItem),
        overrides: [
          upcomingDueBreakdownProvider.overrideWith(
            (ref, item) => const CreditCardBreakdown(totalAmount: 1234567.89, othersShare: 456789.12, transactionCount: 47),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Total Due'), findsOneWidget);
      expect(find.text('My Expenses'), findsOneWidget);
      expect(find.text("Other People's Expenses"), findsOneWidget);
      expect(find.text('View Full Details →'), findsOneWidget);
    });
  }

  for (final scale in _scales) {
    testWidgets('UpcomingDueBreakdownSheet renders a no-interest EMI breakdown without overflow @${scale}x',
        (tester) async {
      final emiItem = (
        kind: UpcomingDueKind.emi,
        title: 'Laptop EMI',
        dueDate: now,
        remaining: 4500.0,
        urgency: PaymentUrgency.upcoming,
        isCarriedOver: false,
        routeId: 'emi1',
        secondaryRouteId: null,
      );
      await pumpAt(
        tester,
        scale,
        UpcomingDueBreakdownSheet(item: emiItem),
        overrides: [
          upcomingDueBreakdownProvider.overrideWith(
            (ref, item) => const EmiBreakdown(amountDue: 4500, principalPortion: null, interestPortion: null),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('No Interest'), findsOneWidget);
    });
  }
}
