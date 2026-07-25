import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/payment_urgency_badge.dart';
import '../providers/upcoming_due_breakdown_provider.dart';
import '../providers/upcoming_due_provider.dart';
import 'upcoming_payments_widget_card.dart' show iconForUpcomingDueKind, openUpcomingDueItem;

/// Ownership-summary sheet shown before navigating away from an Upcoming
/// Due row — "how much of this total is actually mine" for the item the
/// user tapped. Every figure comes from [upcomingDueBreakdownProvider],
/// which only reads/filters/sums fields that already exist elsewhere; this
/// widget is presentation only. The sheet's one action pushes to the same
/// detail route [openUpcomingDueItem] already used, so nothing about
/// navigation changes — a tap just detours through this summary first.
class UpcomingDueBreakdownSheet extends ConsumerWidget {
  const UpcomingDueBreakdownSheet({super.key, required this.item});

  final UpcomingDueItem item;

  static Future<void> show(BuildContext context, UpcomingDueItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpcomingDueBreakdownSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(upcomingDueBreakdownProvider(item));
    final colors = context.colors;
    final textTheme = context.textTheme;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSizes.sm),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.xl, AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconForUpcomingDueKind(item.kind), color: colors.primary),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: PaymentUrgencyBadge(urgency: item.urgency, compact: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xl),
              if (breakdown == null)
                Text(
                  'This item is no longer available.',
                  style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                )
              else
                _BreakdownBody(breakdown: breakdown, format: format),
              const SizedBox(height: AppSizes.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openUpcomingDueItem(context, item);
                  },
                  child: const Text('View Full Details →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownBody extends StatelessWidget {
  const _BreakdownBody({required this.breakdown, required this.format});

  final UpcomingDueBreakdown breakdown;
  final NumberFormat format;

  @override
  Widget build(BuildContext context) {
    return switch (breakdown) {
      CreditCardBreakdown b => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(label: 'Total Due', amount: b.totalAmount, emphasize: true, format: format),
            const _Divider(),
            _AmountRow(label: 'My Expenses', amount: b.myShare, format: format),
            const SizedBox(height: AppSizes.sm),
            _AmountRow(label: "Other People's Expenses", amount: b.othersShare, format: format),
            const _Divider(),
            _AmountRow(label: 'Transactions', value: '${b.transactionCount}', format: format),
          ],
        ),
      BillBreakdown b => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(label: 'Total Due', amount: b.amount, emphasize: true, format: format),
            const _Divider(),
            _AmountRow(label: 'My Expense', amount: b.amount, format: format),
            const SizedBox(height: AppSizes.sm),
            _AmountRow(label: 'Other Expense', amount: 0, format: format),
          ],
        ),
      SplitExpenseBreakdown b => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(label: 'Total', amount: b.total, emphasize: true, format: format),
            const _Divider(),
            _AmountRow(label: 'My Share', amount: b.myShare, format: format),
            const SizedBox(height: AppSizes.sm),
            _AmountRow(label: "Others' Share", amount: b.othersShare, format: format),
          ],
        ),
      EmiBreakdown b => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(label: 'Monthly EMI', amount: b.amountDue, emphasize: true, format: format),
            const _Divider(),
            if (b.hasInterestSplit) ...[
              _AmountRow(label: 'Principal', amount: b.principalPortion!, format: format),
              const SizedBox(height: AppSizes.sm),
              _AmountRow(label: 'Interest', amount: b.interestPortion!, format: format),
            ] else
              _AmountRow(label: 'Interest', value: 'No Interest', format: format),
          ],
        ),
      LoanBreakdown b => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(label: 'Total Outstanding', amount: b.totalOutstanding, emphasize: true, format: format),
            const _Divider(),
            _AmountRow(label: 'Outstanding Principal', amount: b.outstandingPrincipal, format: format),
            const SizedBox(height: AppSizes.sm),
            _AmountRow(label: 'Outstanding Interest', amount: b.outstandingInterest, format: format),
          ],
        ),
    };
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
      child: Divider(height: 1, color: context.colors.onSurface.withValues(alpha: 0.08)),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, this.amount, this.value, this.emphasize = false, required this.format});

  final String label;
  final double? amount;
  final String? value;
  final bool emphasize;
  final NumberFormat format;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final colors = context.colors;
    final displayValue = value ?? format.format(amount);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? textTheme.titleSmall?.copyWith(color: colors.onSurfaceVariant)
                : textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              displayValue,
              style: emphasize
                  ? textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)
                  : textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.expense),
            ),
          ),
        ),
      ],
    );
  }
}
