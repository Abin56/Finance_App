import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../domain/widget_configuration.dart';
import '../../../theme/clay_widgets.dart';
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
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
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
                    ClayIconChip(
                      icon: Icons.account_balance_wallet_outlined,
                      color: Color(account.colorValue),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(account.name, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      format.format(account.currentBalance),
                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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
