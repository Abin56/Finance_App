import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/cash_flow_providers.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';

/// Section 4 of the Cash Flow Center — "Upcoming Payments". A merged
/// timeline across EMI, Loans, Bills, and Credit Card statements, sorted
/// with overdue items always first, then by nearest due date.
class UpcomingPaymentsTimeline extends ConsumerWidget {
  const UpcomingPaymentsTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(upcomingPaymentsTimelineProvider);

    if (items.isEmpty) {
      return const PlaceholderCard(
        icon: Icons.event_note_outlined,
        title: 'No upcoming payments',
        message: 'EMIs, bills, loans, and credit card dues will appear here as they come up.',
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
            child: Text('Upcoming Payments', style: context.textTheme.titleMedium),
          ),
          const SizedBox(height: AppSizes.sm),
          for (final item in items) _TimelineRow(item: item, onTap: () => _onTap(context, item)),
        ],
      ),
    );
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
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.onTap});

  final UpcomingPaymentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.sm),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: item.urgency.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSizes.md),
            SizedBox(
              width: 48,
              child: Text(item.dueDate.shortDate, style: context.textTheme.bodySmall),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(item.title, style: context.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(
              CurrencyFormatter.instance.format(item.remaining),
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: item.urgency.color),
            ),
          ],
        ),
      ),
    );
  }
}
