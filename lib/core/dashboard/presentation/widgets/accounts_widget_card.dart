import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.accounts] — every non-deleted [Account] and
/// its live [Account.currentBalance], filtered to [WidgetConfiguration.accountIds]
/// when non-empty (an empty list means "show all", per [WidgetConfiguration]'s
/// convention).
class AccountsWidgetCard extends ConsumerWidget {
  const AccountsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  static const _maxVisible = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final filtered = config.accountIds.isEmpty
        ? accounts
        : accounts.where((a) => config.accountIds.contains(a.id)).toList();
    final visible = filtered.take(_maxVisible).toList();
    final remaining = filtered.length - visible.length;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(config.title, style: textTheme.labelLarge),
              GestureDetector(
                onTap: () => context.push(AppRoutes.accounts),
                child: Text(
                  'See all ›',
                  style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          if (visible.isEmpty)
            Text('No accounts yet.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else ...[
            for (final account in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                child: Row(
                  children: [
                    Container(
                      width: AppSizes.iconXl,
                      height: AppSizes.iconXl,
                      decoration: BoxDecoration(
                        color: Color(account.colorValue).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.account_balance_wallet_outlined, color: Color(account.colorValue), size: AppSizes.iconMd),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(account.name, style: textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      format.format(account.currentBalance),
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            if (remaining > 0) ...[
              const SizedBox(height: AppSizes.xs),
              Text(
                '+$remaining more',
                style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
