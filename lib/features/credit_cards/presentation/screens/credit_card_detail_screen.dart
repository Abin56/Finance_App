import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/card_network.dart';
import '../../domain/credit_card_profile.dart';
import '../../domain/credit_card_status.dart';
import '../../domain/shared_credit_limit.dart';
import '../../domain/statement.dart';
import '../../domain/statement_status.dart';
import '../providers/credit_card_providers.dart';
import '../widgets/credit_card_form_sheet.dart';

bool _hasCardInfo(CreditCardProfile card) {
  return card.cardNetwork != null ||
      card.lastFourDigits != null ||
      card.annualFee > 0 ||
      card.joiningFee > 0 ||
      card.interestRatePercent != null ||
      (card.rewardNotes != null && card.rewardNotes!.isNotEmpty) ||
      (card.autoPay && card.autoDebitAccount != null) ||
      (card.cardHolderName != null && card.cardHolderName!.isNotEmpty);
}

/// Card metadata not already covered by [_CardUsageCard] — network, last 4
/// digits, fees, reference interest rate, reward notes, and auto debit —
/// only rendered when present, mirroring `EmiDetailScreen`'s "Loan info"
/// section.
class _CardInfoSection extends StatelessWidget {
  const _CardInfoSection({required this.card});

  final CreditCardProfile card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Card info', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          if (card.cardHolderName != null && card.cardHolderName!.isNotEmpty)
            _textRow(context, 'Card holder', card.cardHolderName!),
          if (card.cardNetwork != null) _textRow(context, 'Network', card.cardNetwork!.label),
          if (card.lastFourDigits != null) _textRow(context, 'Card number', '•••• ${card.lastFourDigits}'),
          if (card.annualFee > 0) _amountRow(context, 'Annual fee', card.annualFee),
          if (card.joiningFee > 0) _amountRow(context, 'Joining fee', card.joiningFee),
          if (card.interestRatePercent != null)
            _textRow(context, 'Interest rate', '${card.interestRatePercent}%'),
          if (card.autoPay) _textRow(context, 'Auto debit', card.autoDebitAccount ?? 'Enabled'),
          if (card.rewardNotes != null && card.rewardNotes!.isNotEmpty) ...[
            const SizedBox(height: AppSizes.sm),
            Text(
              card.rewardNotes!,
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.8)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          Flexible(
            child: Text(
              value,
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(BuildContext context, String label, double value) {
    return _textRow(context, label, CurrencyFormatter.instance.format(value));
  }
}

/// One card's Settings (statement/due day, limit, minimum-due%, autopay)
/// plus its statements — the live current cycle first, then every
/// materialized past statement newest-first. Watching
/// [materializeStatementProvider] here is what triggers "materialize on
/// read": opening this screen is the one point in the app where a closed
/// cycle actually gets written as a `Statement` document.
class CreditCardDetailScreen extends ConsumerWidget {
  const CreditCardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Side effect only — materializes a closed cycle's Statement doc if due.
    ref.watch(materializeStatementProvider(cardId));

    final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final card = cards.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final account = ref.watch(accountForCardProvider(cardId));
    final standing = ref.watch(creditCardStandingProvider(cardId));
    final sharedLimit = ref.watch(sharedCreditLimitForCardProvider(cardId));
    final effectiveLimit = sharedLimit?.creditLimit ?? card.creditLimit;
    final current = ref.watch(currentStatementCycleProvider(cardId));
    final statements = [...ref.watch(statementsWithLiveTotalsProvider(cardId))]
      ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            BankAvatar(bankId: account?.bankId, fallbackName: account?.name, size: 32),
            const SizedBox(width: AppSizes.sm),
            Flexible(child: Text(account?.name ?? 'Credit Card', overflow: TextOverflow.ellipsis)),
            if (!card.status.isActive) ...[
              const SizedBox(width: AppSizes.sm),
              _CardStatusChip(status: card.status),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Card Settings',
            onPressed: () => CreditCardFormSheet.show(context, card: card),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          if (!card.status.isActive) ...[
            _ClosedCardNotice(status: card.status),
            const SizedBox(height: AppSizes.lg),
          ],
          if (sharedLimit != null) ...[
            _SharedLimitBanner(sharedLimit: sharedLimit, cardId: cardId),
            const SizedBox(height: AppSizes.lg),
          ],
          _CardUsageCard(
            used: standing.outstanding,
            available: standing.available,
            creditLimit: effectiveLimit,
            currentCycleSpend: standing.currentCycleSpend,
          ),
          if (_hasCardInfo(card)) ...[
            const SizedBox(height: AppSizes.lg),
            _CardInfoSection(card: card),
          ],
          const SizedBox(height: AppSizes.lg),
          Text('Statements', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          if (current != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: _StatementTile(statement: current, isCurrent: true, onTap: null),
            ),
          if (statements.isEmpty && current == null)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No statements yet',
              subtitle: 'Statements appear here once a billing cycle closes.',
            )
          else
            for (final statement in statements)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: _StatementTile(
                  statement: statement,
                  isCurrent: false,
                  onTap: () => context.push('${AppRoutes.creditCards}/$cardId/statements/${statement.id}'),
                ),
              ),
        ],
      ),
    );
  }
}

/// A small tinted pill showing a non-active card's [CreditCardStatus]
/// (Closed / Cancelled) — reused in the AppBar and the cards list.
class _CardStatusChip extends StatelessWidget {
  const _CardStatusChip({required this.status});

  final CreditCardStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        status.label,
        style: context.textTheme.labelSmall?.copyWith(color: status.color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Full-width notice explaining a closed/cancelled card is view-only —
/// shown above its usage card so the status is impossible to miss.
class _ClosedCardNotice extends StatelessWidget {
  const _ClosedCardNotice({required this.status});

  final CreditCardStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Row(
        children: [
          Icon(status.icon, size: AppSizes.iconSm, color: status.color),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              switch (status) {
                CreditCardStatus.cancelled =>
                  'This card is cancelled. It stays here for your records; any remaining balance is still shown.',
                CreditCardStatus.blocked =>
                  'This card is temporarily blocked. It can be reactivated later; any remaining balance is still shown.',
                CreditCardStatus.closed || CreditCardStatus.active =>
                  'This card is closed. It stays here for your records; any remaining balance is still shown.',
              },
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above [_CardUsageCard] when this card draws from a bank-issued
/// shared credit limit (e.g. a Visa/RuPay pair of the same physical card) —
/// names the facility and how many cards draw from it, tappable to open
/// Card Settings where the facility can be changed.
class _SharedLimitBanner extends ConsumerWidget {
  const _SharedLimitBanner({required this.sharedLimit, required this.cardId});

  final SharedCreditLimit sharedLimit;
  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final card = cards.where((c) => c.id == cardId).firstOrNull;
    final memberCount = ref.watch(cardsUnderSharedLimitProvider(sharedLimit.id)).length;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      onTap: card == null ? null : () => CreditCardFormSheet.show(context, card: card),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Row(
          children: [
            Icon(Icons.account_balance_rounded, size: AppSizes.iconSm, color: context.colors.primary),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                'Shared credit limit — ${sharedLimit.name} ($memberCount card${memberCount == 1 ? '' : 's'})',
                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

/// The card's "how much of my limit have I used" hero — a big
/// "₹40,000 of ₹80,000 used" line, a color-escalating [ProgressBar], and a
/// compact Available / This cycle stat row. Plain-language, CRED-like.
class _CardUsageCard extends StatelessWidget {
  const _CardUsageCard({
    required this.used,
    required this.available,
    required this.creditLimit,
    required this.currentCycleSpend,
  });

  final double used;
  final double available;
  final double creditLimit;
  final double currentCycleSpend;

  @override
  Widget build(BuildContext context) {
    final ratio = creditLimit <= 0 ? 0.0 : used / creditLimit;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(text: CurrencyFormatter.instance.format(used)),
                      TextSpan(
                        text: ' of ${CurrencyFormatter.instance.format(creditLimit)} used',
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colors.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(
                '${ratio.asPercent} used',
                style: context.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ratio >= 1
                      ? AppColors.error
                      : ratio >= 0.8
                          ? AppColors.warning
                          : context.colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          ProgressBar(progress: ratio, height: 10),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Available', value: available, color: AppColors.success)),
              Expanded(child: _MiniStat(label: 'This cycle', value: currentCycleSpend)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.statement, required this.isCurrent, required this.onTap});

  final Statement statement;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = statement.status;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: status.color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(isCurrent ? Icons.hourglass_top_rounded : status.icon, color: status.color, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrent
                      ? 'Current cycle · ${statement.periodStart.day}/${statement.periodStart.month} → ${statement.periodEnd.day}/${statement.periodEnd.month}'
                      : '${statement.periodStart.day}/${statement.periodStart.month} → ${statement.periodEnd.day}/${statement.periodEnd.month}',
                  style: context.textTheme.titleSmall,
                ),
                Text(
                  isCurrent ? 'In progress' : status.label,
                  style: context.textTheme.bodySmall?.copyWith(color: isCurrent ? null : status.color),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.instance.format(statement.totalAmount),
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
