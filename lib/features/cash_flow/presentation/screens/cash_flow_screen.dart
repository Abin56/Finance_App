import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/clay_theme.dart';
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
      backgroundColor: AppClay.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppClay.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet_rounded, size: AppSizes.iconSm, color: Colors.white),
            ),
            const SizedBox(width: AppSizes.sm),
            Text(
              'Cash Flow',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          // Bottom padding clears the shell's floating "+" button.
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.fabClearance),
          children: const [
            Align(alignment: Alignment.centerLeft, child: CashFlowPeriodSelector()),
            SizedBox(height: AppSizes.md),
            PaymentsDueCard(),
            SizedBox(height: AppSizes.md),
            MoneyToReceiveCard(),
            SizedBox(height: AppSizes.md),
            UpcomingPaymentsTimeline(),
            SizedBox(height: AppSizes.md),
            CreditCardStatementSummaryCard(),
            SizedBox(height: AppSizes.md),
            CashFlowSummaryCard(),
            SizedBox(height: AppSizes.md),
            MyExpensesCard(),
          ],
        ),
      ),
    );
  }
}
