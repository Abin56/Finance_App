import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../providers/account_providers.dart';
import '../widgets/account_form_sheet.dart';
import '../widgets/account_tile.dart';
import 'accounts_trash_screen.dart';

/// Lists every account with its live balance and net worth across all of
/// them. Swipe to soft-delete (with undo); a trash icon surfaces anything
/// pending permanent deletion.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(accountRepositoryProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final netWorth = ref.watch(netWorthProvider);

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(
        backgroundColor: AppClay.background(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Accounts'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSizes.sm),
            child: ClayIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Trash',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountsTrashScreen()),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ClayFab(
        heroTag: 'accounts_fab',
        icon: Icons.add,
        onPressed: () => AccountFormSheet.show(context),
      ),
      body: SafeArea(child: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              subtitle: 'Add a cash wallet or bank account to start tracking balances.',
              action: FilledButton(
                onPressed: () => AccountFormSheet.show(context),
                child: const Text('Add your first account'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.lg),
                child: ClayCard(
                  isHero: true,
                  padding: const EdgeInsets.all(AppSizes.lg),
                  gradient: const LinearGradient(
                    colors: AppClay.primaryGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Net worth',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSizes.xs),
                      Text(
                        CurrencyFormatter.instance.format(netWorth),
                        style: context.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final account in accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: Dismissible(
                    key: ValueKey(account.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                      decoration: BoxDecoration(
                        color: AppClay.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppClay.radiusCard),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: AppClay.danger),
                    ),
                    onDismissed: (_) async {
                      await repository.softDelete(account);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${account.name} moved to trash'),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () => repository.restore(account),
                          ),
                        ),
                      );
                    },
                    child: AccountTile(
                      account: account,
                      onTap: () => context.push('${AppRoutes.accounts}/${account.id}'),
                    ),
                  ),
                ),
            ],
          );
        },
      )),
    );
  }
}
