import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/dialogs/destructive_delete_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../credit_cards/data/credit_card_deletion_service.dart';
import '../../../credit_cards/domain/credit_card_profile.dart';
import '../../../credit_cards/presentation/providers/credit_card_deletion_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../data/account_deletion_service.dart';
import '../../domain/account.dart';
import '../../domain/account_type.dart';
import '../providers/account_deletion_providers.dart';
import '../providers/account_providers.dart';

/// Soft-deleted accounts awaiting restore or permanent deletion.
/// Demonstrates the generic trash mechanism every future feature
/// (transactions, bills, people) will reuse from [HiveCrudRepository].
class AccountsTrashScreen extends ConsumerWidget {
  const AccountsTrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(accountsTrashStreamProvider);

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(
        backgroundColor: AppClay.background(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Trash'),
      ),
      body: SafeArea(child: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (trashed) {
          if (trashed.isEmpty) {
            return const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is empty',
              subtitle: 'Deleted accounts will appear here until you restore or remove them.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: trashed.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final account = trashed[index];
              return ClayCard(
                child: Row(
                  children: [
                    account.type == AccountType.bank || account.type == AccountType.card
                        ? BankLogo(bankId: account.bankId, fallbackName: account.name, size: 36)
                        : ClayIconChip(icon: account.type.icon, color: AppClay.primary, size: 36, iconSize: 18),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(account.name, style: context.textTheme.titleMedium),
                          Text(
                            'Deleted ${account.deletedAt!.toLocal()}'.split('.').first,
                            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ClayIconButton(
                      icon: Icons.restore_rounded,
                      tooltip: 'Restore',
                      onPressed: () => ref.read(accountRepositoryProvider).restore(account),
                    ),
                    const SizedBox(width: AppSizes.xs),
                    ClayIconButton(
                      icon: Icons.delete_forever_rounded,
                      color: AppClay.danger,
                      tooltip: 'Delete forever',
                      onPressed: () => _confirmPermanentDelete(context, ref, account),
                    ),
                  ],
                ),
              );
            },
          );
        },
      )),
    );
  }

  /// A card-backed account (active or trashed [CreditCardProfile] with
  /// `accountId == account.id`) routes to the credit-card cascade instead of
  /// the plain account one — see `credit_card_deletion_service.dart`. Every
  /// other trashed account (the common case) uses the plain cascade.
  /// `credit_cards_screen.dart`'s own "Delete card" soft-delete action is
  /// untouched by this — this is only the "permanently delete from Trash"
  /// moment.
  Future<void> _confirmPermanentDelete(BuildContext context, WidgetRef ref, Account account) async {
    final creditCardRepository = ref.read(creditCardRepositoryProvider);
    final linkedCard = [...await creditCardRepository.getAll(), ...await creditCardRepository.getTrash()]
        .where((c) => c.accountId == account.id)
        .firstOrNull;

    if (!context.mounted) return;

    if (linkedCard != null) {
      final repos = ref.read(creditCardDeletionRepositoriesProvider);
      await showDestructiveDeleteDialog(
        context,
        entityLabel: 'credit card',
        entityName: account.name,
        loadImpact: () => _creditCardImpactRows(linkedCard, repos),
        onConfirm: () => permanentlyDeleteCreditCardAndHistory(linkedCard, repos),
      );
      return;
    }

    final repos = ref.read(accountDeletionRepositoriesProvider);
    await showDestructiveDeleteDialog(
      context,
      entityLabel: 'account',
      entityName: account.name,
      loadImpact: () => _accountImpactRows(account, repos),
      onConfirm: () async {
        await permanentlyDeleteAccountHistory(account.id, repos);
        await ref.read(accountRepositoryProvider).permanentlyDelete(account);
      },
    );
  }

  Future<List<DestructiveDeleteImpactRow>> _accountImpactRows(
    Account account,
    AccountDeletionRepositories repos,
  ) async {
    final impact = await previewAccountDeletionImpact(account.id, repos);
    return _impactRowsFor(impact);
  }

  Future<List<DestructiveDeleteImpactRow>> _creditCardImpactRows(
    CreditCardProfile card,
    CreditCardDeletionRepositories repos,
  ) async {
    final impact = await previewCreditCardDeletionImpact(card, repos);
    return [
      ..._impactRowsFor(impact.accountImpact),
      DestructiveDeleteImpactRow(label: '${impact.emiCount} linked EMI(s)', count: impact.emiCount),
      DestructiveDeleteImpactRow(label: '${impact.statementCount} statement(s)', count: impact.statementCount),
      DestructiveDeleteImpactRow(
        label: 'Shared credit limit will also be removed (no other card uses it)',
        count: impact.sharedLimitWillBeRemoved ? 1 : 0,
      ),
    ];
  }

  List<DestructiveDeleteImpactRow> _impactRowsFor(AccountDeletionImpact impact) {
    return [
      DestructiveDeleteImpactRow(label: '${impact.transactionCount} transaction(s)', count: impact.transactionCount),
      DestructiveDeleteImpactRow(
        label: '${impact.expenseCount} shared/assigned expense(s)',
        count: impact.expenseCount,
      ),
      DestructiveDeleteImpactRow(
        label: "${impact.affectedPersonCount} person's balance will be recalculated",
        count: impact.affectedPersonCount,
      ),
      DestructiveDeleteImpactRow(label: '${impact.billCount} bill(s) paying from this account', count: impact.billCount),
    ];
  }
}
