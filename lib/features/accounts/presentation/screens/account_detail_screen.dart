import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../transactions/presentation/screens/transactions_screen.dart';
import '../../domain/account.dart';
import '../../domain/account_stats.dart';
import '../../domain/account_type.dart';
import '../providers/account_providers.dart';
import '../providers/account_stats_providers.dart';
import '../widgets/account_form_sheet.dart';

/// One account's balance, activity stats, and a way into its own scoped
/// Transaction History — reached by tapping an account on [AccountsScreen].
/// History itself is never reimplemented here: "View Full History" pushes
/// the existing [TransactionsScreen] pre-filtered to this account, so every
/// search/filter/sort feature it already has works unchanged.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stats = ref.watch(accountStatsProvider(accountId));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (account.type == AccountType.bank ||
                account.type == AccountType.card)
              BankLogo(
                bankId: account.bankId,
                fallbackName: account.name,
                size: 32,
              )
            else
              FlowFiIconChip(
                icon: account.type.icon,
                color: Color(account.colorValue),
                size: 32,
              ),
            const SizedBox(width: AppSizes.sm),
            Flexible(
              child: Text(account.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSizes.sm),
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Account',
              onPressed: () => AccountFormSheet.show(context, account: account),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            _BalanceCard(account: account),
            const SizedBox(height: AppSizes.lg),
            _StatsCard(stats: stats),
            const SizedBox(height: AppSizes.lg),
            _MonthlySpendingCard(
              currentMonthExpense: stats.currentMonthExpense,
            ),
            const SizedBox(height: AppSizes.lg),
            FlowFiCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TransactionsScreen(initialAccountId: accountId),
                ),
              ),
              child: Builder(
                builder: (context) {
                  // Lime only reads well as a fill or on a dark surface (see
                  // the color-usage rule) — as plain text/icon on this light
                  // card it needs the same safe-contrast swap the theme's own
                  // text buttons use: near-black in light mode, lime in dark.
                  final accentColor = context.isDarkMode
                      ? AppColors.primaryDark
                      : context.colors.onSurface;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: accentColor,
                        size: AppSizes.iconSm,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Text(
                        'View Full History',
                        style: context.textTheme.labelLarge?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    return FlowFiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.type.label,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            CurrencyFormatter.instance.format(account.currentBalance),
            style: context.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final AccountStats stats;

  @override
  Widget build(BuildContext context) {
    return FlowFiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Statistics', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Income',
                  value: stats.income,
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _Stat(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Expense',
                  value: stats.expense,
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowFiIconChip(icon: icon, color: color),
        const SizedBox(height: AppSizes.xs),
        Text(
          CurrencyFormatter.instance.formatCompact(value),
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurface.withValues(alpha: 0.6),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MonthlySpendingCard extends StatelessWidget {
  const _MonthlySpendingCard({required this.currentMonthExpense});

  final double currentMonthExpense;

  @override
  Widget build(BuildContext context) {
    return FlowFiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly Spending · ${DateTime.now().monthYear}',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            CurrencyFormatter.instance.format(currentMonthExpense),
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.expense,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
