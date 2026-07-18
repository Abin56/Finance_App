import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/card_network.dart';
import '../../domain/credit_card_status.dart';
import '../providers/credit_card_providers.dart';
import '../widgets/credit_card_form_sheet.dart';

/// Every credit card, each tile showing Remaining to Pay/Available/Next Due —
/// mirrors [BillsScreen]'s list-of-entities shape without the search/filter
/// chrome (out of scope for this pass; a handful of cards doesn't need it
/// the way a long bill list does).
class CreditCardsScreen extends ConsumerWidget {
  const CreditCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(creditCardsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final accountNameById = {for (final a in accounts) a.id: a.name};
    final accountBankIdById = {for (final a in accounts) a.id: a.bankId};

    return Scaffold(
      appBar: AppBar(title: const Text('Credit Cards')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'credit_cards_fab',
        onPressed: () => CreditCardFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        // Loading/error state comes from the raw stream above; the actual
        // list to render is `activeCreditCardsProvider` — excludes cards
        // whose linked Account has been deleted (there's no delete action
        // for a card itself, so this is how a removed card actually
        // disappears from the list; see that provider's doc comment).
        data: (_) {
          final cards = ref.watch(activeCreditCardsProvider);
          if (cards.isEmpty) {
            return EmptyState(
              icon: Icons.credit_card_outlined,
              title: 'No credit cards yet',
              subtitle: 'Add a card to track its statement cycle and remaining balance.',
              action: FilledButton(
                onPressed: () => CreditCardFormSheet.show(context),
                child: const Text('Add your first card'),
              ),
            );
          }

          // Active cards first; closed/cancelled sink to the bottom.
          final sortedCards = [...cards]
            ..sort((a, b) => (a.status.isActive ? 0 : 1).compareTo(b.status.isActive ? 0 : 1));

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              for (final card in sortedCards)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: _CreditCardTile(
                    name: accountNameById[card.accountId] ?? 'Card',
                    bankId: accountBankIdById[card.accountId],
                    cardId: card.id,
                    status: card.status,
                    cardNetwork: card.cardNetwork,
                    lastFourDigits: card.lastFourDigits,
                    onTap: () => context.push('${AppRoutes.creditCards}/${card.id}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CreditCardTile extends ConsumerWidget {
  const _CreditCardTile({
    required this.name,
    required this.cardId,
    required this.status,
    required this.onTap,
    this.bankId,
    this.cardNetwork,
    this.lastFourDigits,
  });

  final String name;
  final String? bankId;
  final String cardId;
  final CreditCardStatus status;
  final CardNetwork? cardNetwork;
  final String? lastFourDigits;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(cardId));
    final nextDue = ref.watch(statementsStreamProvider(cardId)).value
        ?.where((s) => s.remainingAmount > 0)
        .fold<DateTime?>(null, (soonest, s) => soonest == null || s.dueDate.isBefore(soonest) ? s.dueDate : soonest);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BankAvatar(bankId: bankId, fallbackName: name, size: 32),
              const SizedBox(width: AppSizes.sm),
              if (cardNetwork != null) ...[
                Icon(cardNetwork!.icon, size: AppSizes.iconSm),
                const SizedBox(width: AppSizes.xs),
              ],
              Flexible(
                child: Text(
                  lastFourDigits == null ? name : '$name •••• $lastFourDigits',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!status.isActive) ...[
                const SizedBox(width: AppSizes.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Text(
                    status.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: status.color, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            // Values sit above their labels, and "Remaining to Pay" wraps to two
            // lines in a third-width column on a 360dp phone. Top-align so the
            // wrapped label can't push its value out of line with the others.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(label: 'Remaining to Pay', value: CurrencyFormatter.instance.format(standing.outstanding)),
              ),
              Expanded(
                child: _Stat(label: 'Available', value: CurrencyFormatter.instance.format(standing.available)),
              ),
              Expanded(
                child: _Stat(
                  label: 'Next due',
                  value: nextDue == null ? '—' : '${nextDue.day}/${nextDue.month}',
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
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}
