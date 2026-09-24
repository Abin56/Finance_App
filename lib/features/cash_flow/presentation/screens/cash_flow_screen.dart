import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../widgets/cash_flow_period_selector.dart';
import '../widgets/cash_flow_summary_card.dart';
import '../widgets/credit_card_statement_summary_card.dart';
import '../widgets/money_to_receive_card.dart';
import '../widgets/my_expenses_card.dart';
import '../widgets/payments_due_card.dart';
import '../widgets/upcoming_payments_timeline.dart';

/// The Cash Flow tab — the app's financial planning center, as distinct
/// from Reports (analysis of the past). Surfaces what's due, what's owed
/// to the user, what's coming up, and this month's net flow, each card
/// reusing the same aggregation providers/widgets the Dashboard used
/// before this screen existed; nothing here recomputes anything.
class CashFlowScreen extends StatelessWidget {
  const CashFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Low-noise app bar — background blends with the scaffold, no
      // elevation, no gradient. The screen's net-cash-flow "hero" emphasis
      // now lives in the body as a `FlowFiCard.hero` (see
      // `CashFlowSummaryCard`) instead of a gradient flexibleSpace here.
      appBar: AppBar(title: const Text('Cash Flow')),
      body: SafeArea(
        child: ListView(
          // Bottom padding clears the shell's floating "+" button.
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.lg,
            AppSizes.lg,
            AppSizes.fabClearance,
          ),
          children: const [
            CashFlowSummaryCard(),
            SizedBox(height: AppSizes.md),
            Align(
              alignment: Alignment.centerLeft,
              child: CashFlowPeriodSelector(),
            ),
            SizedBox(height: AppSizes.md),
            PaymentsDueCard(),
            SizedBox(height: AppSizes.md),
            MoneyToReceiveCard(),
            SizedBox(height: AppSizes.md),
            UpcomingPaymentsTimeline(),
            SizedBox(height: AppSizes.md),
            CreditCardStatementSummaryCard(),
            SizedBox(height: AppSizes.md),
            MyExpensesCard(),
          ],
        ),
      ),
    );
  }
}
