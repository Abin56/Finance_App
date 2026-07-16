import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/states/payment_urgency_badge.dart';
import '../../../../shared/widgets/states/shimmer_box.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import 'dashboard_preview_row.dart';
import 'dashboard_section_card.dart';

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

  void _onTap(BuildContext context, UpcomingPaymentItem item) {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Approximation: these are the top-level lists the timeline aggregates
    // from (see upcomingPaymentsTimelineProvider). Per-item installment
    // streams resolve near-instantly once these are known, so a rare
    // false-negative here is cosmetic only — the skeleton disappearing a
    // beat early, never a data-correctness issue.
    final loading = ref.watch(emisStreamProvider).isLoading ||
        ref.watch(loansStreamProvider).isLoading ||
        ref.watch(billsStreamProvider).isLoading ||
        ref.watch(creditCardsStreamProvider).isLoading;
    if (loading) {
      return const DashboardSectionCard(child: _UpcomingPaymentsSkeleton());
    }

    final items = ref.watch(upcomingPaymentsTimelineProvider).take(3).toList();

    if (items.isEmpty) {
      return PlaceholderCard(
        icon: Icons.event_note_outlined,
        title: 'No upcoming payments',
        message: 'EMIs, bills, loans, and credit card dues will appear here as they come up.',
        radius: AppSizes.radiusCard,
        actionLabel: 'Open Cash Flow',
        onTap: () => context.push(AppRoutes.cashFlow),
      );
    }

    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            DashboardPreviewRow(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(_iconFor(item.kind), color: AppColors.primary),
              ),
              title: item.title,
              caption: _dueLabel(item.dueDate),
              amount: item.remaining,
              statusBadge: PaymentUrgencyBadge(urgency: item.urgency, compact: true),
              onTap: () => _onTap(context, item),
            ),
        ],
      ),
    );
  }
}

class _UpcomingPaymentsSkeleton extends StatelessWidget {
  const _UpcomingPaymentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: AppSizes.md),
          Row(
            children: [
              const ShimmerBox(width: 44, height: 44, borderRadius: AppSizes.radiusPill),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(width: 130, height: 16),
                    SizedBox(height: AppSizes.xs),
                    ShimmerBox(width: 70, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              const ShimmerBox(width: 60, height: 16),
            ],
          ),
        ],
      ],
    );
  }
}
