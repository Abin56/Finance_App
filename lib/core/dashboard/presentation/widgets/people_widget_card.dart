import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/people/presentation/providers/people_providers.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.people] — the two ledger totals the Contact
/// Ledger already owns, side by side with deliberately plain labels: "You
/// Owe" ([totalPayableProvider]) and "Owed to You" ([totalReceivableProvider]).
/// Each tile opens the matching full list (Debtors / Creditors); nothing is
/// netted into a single figure here, since "you owe ₹500 and are owed ₹500"
/// is not the same situation as "all settled".
class PeopleWidgetCard extends ConsumerWidget {
  const PeopleWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final youOwe = ref.watch(totalPayableProvider);
    final owedToYou = ref.watch(totalReceivableProvider);
    final debtorCount = ref.watch(debtorsProvider).length;
    final creditorCount = ref.watch(creditorsProvider).length;
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () => context.go(AppRoutes.people),
                child: Text(
                  'See all ›',
                  style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (youOwe == 0 && owedToYou == 0)
            Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: AppSizes.iconMd, color: AppColors.success),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'All settled — nothing owed either way.',
                    style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _BalanceTile(
                    label: 'You Owe',
                    amount: youOwe,
                    caption: youOwe == 0 ? 'No one' : 'to $debtorCount ${debtorCount == 1 ? 'person' : 'people'}',
                    color: AppColors.expense,
                    icon: Icons.arrow_upward_rounded,
                    onTap: () => context.push(AppRoutes.debtors),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: _BalanceTile(
                    label: 'Owed to You',
                    amount: owedToYou,
                    caption: owedToYou == 0
                        ? 'No one'
                        : 'from $creditorCount ${creditorCount == 1 ? 'person' : 'people'}',
                    color: AppColors.income,
                    icon: Icons.arrow_downward_rounded,
                    onTap: () => context.push(AppRoutes.creditors),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.label,
    required this.amount,
    required this.caption,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final double amount;
  final String caption;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: AppSizes.iconSm, color: color),
                  const SizedBox(width: AppSizes.xs),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  format.format(amount),
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
