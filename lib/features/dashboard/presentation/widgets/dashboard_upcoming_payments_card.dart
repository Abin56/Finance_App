import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/states/payment_urgency_badge.dart';
import '../../../cash_flow/presentation/providers/cash_flow_providers.dart';

/// Dashboard-scale preview of the Cash Flow Center's unified upcoming-
/// payments timeline ([upcomingPaymentsTimelineProvider], already computed
/// there from EMI/Loan/Bill/Credit Card data) — the top 3 items, styled to
/// match the Figma "Upcoming Payments" card. "View all" opens the full
/// Cash Flow tab where every item lives.
class DashboardUpcomingPaymentsCard extends ConsumerWidget {
  const DashboardUpcomingPaymentsCard({super.key});

  IconData _iconFor(UpcomingPaymentKind kind) {
    switch (kind) {
      case UpcomingPaymentKind.emi:
        return Icons.calendar_month_rounded;
      case UpcomingPaymentKind.loan:
        return Icons.account_balance_rounded;
      case UpcomingPaymentKind.bill:
        return Icons.bolt_rounded;
      case UpcomingPaymentKind.creditCard:
        return Icons.credit_card_rounded;
    }
  }

  String _dueLabel(DateTime dueDate) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = due.difference(today).inDays;
    if (days < 0) return 'Overdue by ${-days}d';
    if (days == 0) return 'Due today';
    return 'Due in ${days}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(upcomingPaymentsTimelineProvider).take(3).toList();

    if (items.isEmpty) {
      return const PlaceholderCard(
        icon: Icons.event_note_outlined,
        title: 'No upcoming payments',
        message: 'EMIs, bills, loans, and credit card dues will appear here as they come up.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items) _PaymentRow(item: item, icon: _iconFor(item.kind), dueLabel: _dueLabel(item.dueDate)),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.item, required this.icon, required this.dueLabel});

  final UpcomingPaymentItem item;
  final IconData icon;
  final String dueLabel;

  void _onTap(BuildContext context) {
    switch (item.kind) {
      case UpcomingPaymentKind.emi:
        context.push('${AppRoutes.emis}/${item.routeId}');
      case UpcomingPaymentKind.loan:
        context.push('${AppRoutes.loans}/${item.routeId}');
      case UpcomingPaymentKind.bill:
        context.push('${AppRoutes.bills}/${item.routeId}');
      case UpcomingPaymentKind.creditCard:
        context.push('${AppRoutes.creditCards}/${item.routeId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _onTap(context),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: context.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    dueLabel,
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.instance.format(item.remaining),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                PaymentUrgencyBadge(urgency: item.urgency, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
