import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/cash_flow/presentation/widgets/upcoming_payments_timeline.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [UpcomingPaymentsTimeline] rows now carry a "Carried Forward" badge for
/// [UpcomingPaymentItem.isCarriedOver] items (Phase 1's carry-forward
/// consolidation added that field; Phase 6 wires it into this row) —
/// checked on a small (360dp) phone since the badge adds a second text
/// line under a title that already has to share space with the trailing
/// amount.
const _smallPhone = Size(360, 640);
const _scales = [1.0, 1.3, 2.0];

void main() {
  final now = DateTime.now();
  final items = [
    (
      kind: UpcomingPaymentKind.creditCard,
      title: 'A Fairly Long Card Name •••• 4321',
      dueDate: now.subtract(const Duration(days: 20)),
      amountDue: 123456.78,
      remaining: 98765.43,
      urgency: PaymentUrgency.carriedForward,
      isCarriedOver: true,
      routeId: 'card1',
    ),
    (
      kind: UpcomingPaymentKind.bill,
      title: 'Electricity',
      dueDate: now.add(const Duration(days: 3)),
      amountDue: 2000.0,
      remaining: 2000.0,
      urgency: PaymentUrgency.dueSoon,
      isCarriedOver: false,
      routeId: 'bill1',
    ),
  ];

  Future<void> pumpAt(WidgetTester tester, double scale) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [upcomingPaymentsTimelineProvider.overrideWithValue(items)],
        child: MaterialApp(
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: inner!,
          ),
          home: const Scaffold(body: SingleChildScrollView(child: UpcomingPaymentsTimeline())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in _scales) {
    testWidgets('renders carried-over and normal rows without overflow @${scale}x', (tester) async {
      await pumpAt(tester, scale);
      expect(tester.takeException(), isNull);
      expect(find.text('Carried Forward'), findsOneWidget);
    });
  }
}
