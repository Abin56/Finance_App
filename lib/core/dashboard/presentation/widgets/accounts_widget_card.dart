import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/accounts/domain/account.dart';
import '../../../../features/accounts/presentation/providers/account_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import 'dashboard_format.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.accounts] — money actually held: the
/// "Total balance" headline is [cashBalanceProvider] (every account except
/// tracked credit-card accounts, whose negative balance is card debt — the
/// same rule as Web's Accounts overview), followed by those cash accounts.
/// Card accounts aren't listed as if they were money; the Credit sections
/// show them. Filtered to [WidgetConfiguration.accountIds] when non-empty
/// (empty means "show all").
class AccountsWidgetCard extends ConsumerWidget {
  const AccountsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  static const _maxVisible = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final cardsAsync = ref.watch(creditCardsStreamProvider);
    final load = SectionLoad.of([accountsAsync, cardsAsync]);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            title: config.title,
            subtitle: 'Total balance · excludes credit cards',
            actionLabel: 'All',
            onAction: () => context.push(AppRoutes.accounts),
          ),
          const SizedBox(height: AppSizes.xs),
          DashboardSectionBody(
            load: load,
            skeletonLeadingHeight: 28,
            errorMessage: "Couldn't load your accounts.",
            onRetry: () => invalidateDashboardSources(ref),
            builder: (context) {
              final cardAccountIds = {
                for (final c in cardsAsync.requireValue) c.accountId,
              };
              final all = config.accountIds.isEmpty
                  ? accountsAsync.requireValue
                  : accountsAsync.requireValue
                        .where((a) => config.accountIds.contains(a.id))
                        .toList();
              final cash = all
                  .where((a) => !cardAccountIds.contains(a.id))
                  .toList();
              final total = config.accountIds.isEmpty
                  ? ref.watch(cashBalanceProvider)
                  : cash.fold(0.0, (s, a) => s + a.currentBalance);
              return _AccountsBody(
                cash: cash,
                total: total,
                cardCount: all.length - cash.length,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountsBody extends StatelessWidget {
  const _AccountsBody({
    required this.cash,
    required this.total,
    required this.cardCount,
  });

  final List<Account> cash;
  final double total;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final colors = context.colors;
    if (cash.isEmpty && cardCount == 0) {
      return DashboardEmptyLine(
        icon: Icons.account_balance_wallet_outlined,
        message: 'No accounts yet.',
        actionLabel: 'Add account',
        onAction: () => context.push(AppRoutes.accounts),
      );
    }
    final visible = cash.take(AccountsWidgetCard._maxVisible).toList();
    final remaining = cash.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRupees(total),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: total < 0 ? AppColors.expense : colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        for (final account in visible) _AccountRow(account: account),
        if (remaining > 0 || cardCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.xs),
            child: Text(
              [
                if (remaining > 0) '+$remaining more',
                if (cardCount > 0)
                  '$cardCount credit card account${cardCount == 1 ? '' : 's'}'
                      ' shown under Credit',
              ].join(' · '),
              style: textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      onTap: () => context.push('/accounts/${account.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            if (account.bankId != null)
              BankLogo(
                bankId: account.bankId,
                fallbackName: account.name,
                size: 28,
              )
            else
              FlowFiIconChip(
                icon: Icons.account_balance_wallet_outlined,
                color: Color(account.colorValue),
                size: 28,
                iconSize: 14,
              ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                account.name,
                style: textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatRupees(account.currentBalance),
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: account.currentBalance < 0
                        ? AppColors.expense
                        : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
