import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/animations/count_up_text.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../transactions/presentation/screens/transactions_screen.dart';
import '../../domain/credit_card_profile.dart';
import '../../domain/credit_card_status.dart';
import '../providers/credit_card_providers.dart';
import '../widgets/add_card_to_shared_limit_sheet.dart';
import '../widgets/credit_card_form_sheet.dart';
import '../widgets/credit_card_visual.dart';

/// "My Cards" — a premium wallet-style overview: a swipeable hero carousel of
/// every card's face, a quick-action row, a credit-limit summary (standalone
/// cards individually, shared facilities pooled), and a flat scannable list
/// of every card with its own Available/Statement/Due. Same data and actions
/// as before (add/edit/deactivate/delete a card, add a card to a shared
/// limit, jump to a statement or that card's transactions) — only the visual
/// language changed, modeled on the reference wallet screen.
class CreditCardsScreen extends ConsumerStatefulWidget {
  const CreditCardsScreen({super.key});

  @override
  ConsumerState<CreditCardsScreen> createState() => _CreditCardsScreenState();
}

class _CreditCardsScreenState extends ConsumerState<CreditCardsScreen> {
  int _frontIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(creditCardsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final accountNameById = {for (final a in accounts) a.id: a.name};
    final accountBankIdById = {for (final a in accounts) a.id: a.bankId};
    final accountColorById = {for (final a in accounts) a.id: a.colorValue};

    return Scaffold(
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        // Loading/error state comes from the raw stream above; the actual
        // list to render is `activeCreditCardsProvider` — excludes cards
        // whose linked Account has been soft-deleted (each card's overflow
        // menu offers "Delete card", which soft-deletes that Account).
        data: (_) {
          final cards = ref.watch(activeCreditCardsProvider);
          if (cards.isEmpty) {
            return CustomScrollView(
              slivers: [
                _SliverHeader(hasCards: false),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.credit_card_outlined,
                    title: 'No credit cards yet',
                    subtitle: 'Add a card to track its statement cycle and remaining balance.',
                    action: FilledButton(
                      onPressed: () => CreditCardFormSheet.show(context),
                      child: const Text('Add your first card'),
                    ),
                  ),
                ),
              ],
            );
          }

          final sortedCards = List<CreditCardProfile>.of(cards)
            // Active cards first; closed/cancelled sink to the bottom.
            ..sort((a, b) => (a.status.isActive ? 0 : 1).compareTo(b.status.isActive ? 0 : 1));
          final frontIndex = _frontIndex.clamp(0, sortedCards.length - 1);
          final frontCard = sortedCards[frontIndex];

          return CustomScrollView(
            slivers: [
              _SliverHeader(hasCards: true),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                sliver: SliverToBoxAdapter(
                  child: _HeroCarousel(
                    cards: sortedCards,
                    accountNameById: accountNameById,
                    accountBankIdById: accountBankIdById,
                    accountColorById: accountColorById,
                    frontIndex: frontIndex,
                    onFrontIndexChanged: (index) => setState(() => _frontIndex = index),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, 0),
                sliver: SliverToBoxAdapter(child: _QuickActionsRow(card: frontCard)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, 0),
                sliver: SliverList.list(
                  children: [
                    _CardStandingSummaryCard(
                      card: frontCard,
                      colorValue: accountColorById[frontCard.accountId],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    _StandaloneLimitSummaryCard(cards: sortedCards),
                    const SizedBox(height: AppSizes.lg),
                    _AllCardsSection(
                      cards: sortedCards,
                      accountNameById: accountNameById,
                      accountBankIdById: accountBankIdById,
                      accountColorById: accountColorById,
                      roleLabelById: _sharedLimitRoleLabels(cards),
                    ),
                    const SizedBox(height: AppSizes.fabClearance),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "Primary Card" for the first-added card under a shared limit, "Secondary
/// Card" for the second, "Additional Card" for every one after — derived
/// purely from [CreditCardProfile.createdAt] order within each
/// [CreditCardProfile.sharedLimitId] group, since this app stores no
/// separate role field. Standalone cards (no shared limit) get no label —
/// "primary/secondary" is only a meaningful distinction when cards share one
/// facility.
Map<String, String> _sharedLimitRoleLabels(List<CreditCardProfile> cards) {
  final bySharedLimit = <String, List<CreditCardProfile>>{};
  for (final card in cards) {
    final sharedLimitId = card.sharedLimitId;
    if (sharedLimitId == null) continue;
    bySharedLimit.putIfAbsent(sharedLimitId, () => []).add(card);
  }

  final labels = <String, String>{};
  for (final group in bySharedLimit.values) {
    if (group.length < 2) continue;
    final ordered = List<CreditCardProfile>.of(group)..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (var i = 0; i < ordered.length; i++) {
      labels[ordered[i].id] = switch (i) {
        0 => 'Primary Card',
        1 => 'Secondary Card',
        _ => 'Additional Card',
      };
    }
  }
  return labels;
}

/// Large page title + subtitle + a pill "Add Card" action — replaces the
/// plain AppBar so the header can grow to match the hero carousel's premium
/// feel while still pinning to the top as a normal (non-floating) sliver.
class _SliverHeader extends StatelessWidget {
  const _SliverHeader({required this.hasCards});

  final bool hasCards;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(AppSizes.lg, context.viewPadding.top + AppSizes.sm, AppSizes.lg, AppSizes.md),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'My Cards',
                    style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage your cards and credit limit',
                    style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            if (hasCards) ...[
              const SizedBox(width: AppSizes.md),
              _AddCardButton(compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddCardButton extends StatelessWidget {
  const _AddCardButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.primaryContainer,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CreditCardFormSheet.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: context.colors.onPrimaryContainer),
              const SizedBox(height: 2),
              Text(
                'Add Card',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A fanned wallet-card deck — the front card sits flush left at full
/// width, and every other card peeks out from behind its right edge as a
/// thin colored sliver (narrower/more-covered the further back it sits),
/// matching the reference design's stacked-deck look. Tapping a peeking
/// sliver brings that card to the front; tapping the front card opens it.
class _HeroCarousel extends StatelessWidget {
  const _HeroCarousel({
    required this.cards,
    required this.accountNameById,
    required this.accountBankIdById,
    required this.accountColorById,
    required this.frontIndex,
    required this.onFrontIndexChanged,
  });

  final List<CreditCardProfile> cards;
  final Map<String, String> accountNameById;
  final Map<String, String?> accountBankIdById;
  final Map<String, int> accountColorById;
  final int frontIndex;
  final ValueChanged<int> onFrontIndexChanged;

  @override
  Widget build(BuildContext context) {
    final count = cards.length;
    // Every card after the front one peeks by this many pixels of its
    // right edge, stacked in order so the deck reads back-to-front, left
    // to right — the reference design's fanned wallet look.
    const peekWidth = 26.0;
    const maxPeeks = 4;
    final behindCount = (count - 1).clamp(0, maxPeeks);

    return AspectRatio(
      aspectRatio: 1.85,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frontWidth = constraints.maxWidth - (peekWidth * behindCount);
          // Deck order behind the front card, nearest-behind first.
          final order = [
            for (var offset = 1; offset < count; offset++) (frontIndex + offset) % count,
          ];

          return Stack(
            children: [
              // Painted back-to-front so nearer cards' slivers sit on top.
              for (var i = order.length - 1; i >= 0; i--)
                _buildPeekingCard(context, order[i], depth: i, peekWidth: peekWidth, maxPeeks: maxPeeks),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: frontWidth,
                child: GestureDetector(
                  onTap: () => _CardQuickDetailSheet.show(context, card: cards[frontIndex]),
                  onHorizontalDragEnd: count > 1
                      ? (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity < -100) {
                            onFrontIndexChanged((frontIndex + 1) % count);
                          } else if (velocity > 100) {
                            onFrontIndexChanged((frontIndex - 1 + count) % count);
                          }
                        }
                      : null,
                  child: _HeroCardFace(
                    key: ValueKey(cards[frontIndex].id),
                    card: cards[frontIndex],
                    name: accountNameById[cards[frontIndex].accountId] ?? 'Card',
                    bankId: accountBankIdById[cards[frontIndex].accountId],
                    colorValue: accountColorById[cards[frontIndex].accountId],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPeekingCard(
    BuildContext context,
    int index, {
    required int depth,
    required double peekWidth,
    required int maxPeeks,
  }) {
    if (depth >= maxPeeks) return const SizedBox.shrink();
    final card = cards[index];
    final colorValue = accountColorById[card.accountId] ?? context.colors.primary.toARGB32();
    final base = Color(colorValue);
    // Each card behind the front one occupies its own fixed-width slot,
    // shifted further right the deeper it sits — rather than a single
    // widening block — so every card's own right edge stays visible as a
    // distinct sliver, each set slightly further back (smaller, darker),
    // matching the reference design's fanned-deck look.
    const gap = 3.0;
    final inset = 6.0 * depth;

    return Positioned(
      right: peekWidth * depth,
      top: inset,
      bottom: inset,
      width: peekWidth - gap,
      child: GestureDetector(
        onTap: () => onFrontIndexChanged(index),
        child: Container(
          decoration: BoxDecoration(
            color: Color.lerp(base, Colors.black, 0.15 + (depth * 0.15)),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),
    );
  }
}

class _HeroCardFace extends StatelessWidget {
  const _HeroCardFace({super.key, required this.card, required this.name, this.bankId, this.colorValue});

  final CreditCardProfile card;
  final String name;
  final String? bankId;
  final int? colorValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: AppShadows.soft(context),
      ),
      // The hero slot's own AspectRatio (1.62, to leave room for the fanned
      // peeks) differs from CreditCardVisual's forced internal AspectRatio
      // (1.42, a standard bank-card ratio), so the outer Stack centers the
      // shorter card face instead of letting it hug the top of the taller
      // slot. The status pill is nested in its own Stack scoped to the card
      // face itself, so it anchors to the card's corner, not the outer slot.
      child: Stack(
        alignment: Alignment.center,
        children: [
          Stack(
            children: [
              CreditCardVisual(
                title: name,
                colorValue: colorValue ?? context.colors.primary.toARGB32(),
                bankId: bankId,
                cardNetwork: card.cardNetwork,
                lastFourDigits: card.lastFourDigits,
              ),
              if (!card.status.isActive)
                Positioned(
                  top: AppSizes.md,
                  left: AppSizes.md,
                  child: _StatusPill(status: card.status),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quick-glance detail sheet for the hero card's own figures — shown when
/// the hero card face is tapped, instead of jumping straight to the full
/// statement screen. Shows just this one card's Available/Total/Used and
/// next due date, with a button through to the existing detail screen for
/// anyone who wants the full statement history.
class _CardQuickDetailSheet extends ConsumerWidget {
  const _CardQuickDetailSheet({required this.card});

  final CreditCardProfile card;

  static Future<void> show(BuildContext context, {required CreditCardProfile card}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CardQuickDetailSheet(card: card),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(card.id));
    final nextDue = ref
        .watch(statementsWithLiveTotalsProvider(card.id))
        .where((s) => s.remainingAmount > 0)
        .fold<DateTime?>(null, (soonest, s) => soonest == null || s.dueDate.isBefore(soonest) ? s.dueDate : soonest);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              card.lastFourDigits != null && card.lastFourDigits!.isNotEmpty
                  ? '•••• ${card.lastFourDigits}'
                  : 'Card details',
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(child: _QuickDetailStat(label: 'Available', value: standing.available)),
                Expanded(child: _QuickDetailStat(label: 'Total Limit', value: card.creditLimit)),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                Expanded(child: _QuickDetailStat(label: 'Used', value: standing.outstanding)),
                Expanded(
                  child: _QuickDetailStat.text(label: 'Next Due', text: _CardListTile._dueLabel(nextDue)),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('${AppRoutes.creditCards}/${card.id}');
                },
                child: const Text('View Full Statement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickDetailStat extends StatelessWidget {
  const _QuickDetailStat({required this.label, required double this.value}) : text = null;

  const _QuickDetailStat.text({required this.label, required this.text}) : value = null;

  final String label;
  final double? value;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 2),
        Text(
          text ?? CurrencyFormatter.instance.format(value!),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Statement / Transactions / Edit / More — the quick-action row from the
/// reference design, scoped to whichever card leads the hero carousel. Maps
/// only onto actions this app actually has (no card-lock toggle exists in
/// this codebase, so it's omitted rather than faked).
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.card});

  final CreditCardProfile card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: AppShadows.soft(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.receipt_long_outlined,
              label: 'Statement',
              onTap: () => context.push('${AppRoutes.creditCards}/${card.id}'),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.receipt_outlined,
              label: 'Transactions',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TransactionsScreen(initialAccountId: card.accountId)),
              ),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () => CreditCardFormSheet.show(context, card: card),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.add_rounded,
              label: 'Add Card',
              onTap: () => CreditCardFormSheet.show(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: AppSizes.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: context.textTheme.labelSmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero carousel's current front card's own standing — gradient hero,
/// Total/Available/Used, and a zoned utilization bar (Good/High/Over Limit)
/// with the animated percent read-out. Swaps to whichever card the user has
/// scrolled/tapped to the front of the carousel: a shared-limit card shows
/// its facility's pooled figures (every sibling reports the same numbers),
/// a standalone card shows its own.
class _CardStandingSummaryCard extends ConsumerWidget {
  const _CardStandingSummaryCard({required this.card, this.colorValue});

  final CreditCardProfile card;
  final int? colorValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(card.id));
    final sharedLimit = ref.watch(sharedCreditLimitForCardProvider(card.id));
    final memberCards = sharedLimit == null ? const <CreditCardProfile>[] : ref.watch(cardsUnderSharedLimitProvider(sharedLimit.id));
    final totalLimit = sharedLimit?.creditLimit ?? card.creditLimit;
    final ratio = totalLimit <= 0 ? 0.0 : (standing.outstanding / totalLimit).clampedProgress;
    final base = Color(colorValue ?? context.colors.primary.toARGB32());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LimitSummaryCard(
          title: sharedLimit != null ? '${sharedLimit.name} Shared Credit Limit' : 'Card Credit Limit',
          totalLimit: totalLimit,
          available: standing.available,
          used: standing.outstanding,
          ratio: ratio,
          gradientColors: [base, Color.lerp(base, Colors.black, 0.4)!],
        ),
        if (sharedLimit != null) ...[
          const SizedBox(height: AppSizes.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  memberCards.length == 1 ? '1 physical card' : '${memberCards.length} physical cards',
                  style: context.textTheme.labelLarge?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () => AddCardToSharedLimitSheet.show(context, sharedLimit: sharedLimit),
                icon: const Icon(Icons.add_rounded, size: AppSizes.iconSm),
                label: const Text('Add another card'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The pooled total across every card/facility the user has — same
/// "Total/Available/Used + utilization" summary shape, so a glance below
/// the per-card container above shows the combined credit picture. Counts
/// a shared facility's limit/standing exactly once no matter how many
/// member cards draw from it.
class _StandaloneLimitSummaryCard extends ConsumerWidget {
  const _StandaloneLimitSummaryCard({required this.cards});

  final List<CreditCardProfile> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var totalLimit = 0.0;
    var totalAvailable = 0.0;
    var totalOutstanding = 0.0;
    final countedSharedLimits = <String>{};
    for (final card in cards) {
      if (card.sharedLimitId != null) {
        if (!countedSharedLimits.add(card.sharedLimitId!)) continue;
        final sharedLimit = ref.watch(sharedCreditLimitForCardProvider(card.id));
        final standing = ref.watch(creditCardStandingProvider(card.id));
        totalLimit += sharedLimit?.creditLimit ?? 0;
        totalAvailable += standing.available;
        totalOutstanding += standing.outstanding;
      } else {
        final standing = ref.watch(creditCardStandingProvider(card.id));
        totalLimit += card.creditLimit;
        totalAvailable += standing.available;
        totalOutstanding += standing.outstanding;
      }
    }
    final ratio = totalLimit <= 0 ? 0.0 : (totalOutstanding / totalLimit).clampedProgress;

    return _LimitSummaryCard(
      title: 'Total Credit Limit',
      totalLimit: totalLimit,
      available: totalAvailable,
      used: totalOutstanding,
      ratio: ratio,
    );
  }
}

/// Shared visual for both the per-facility and the pooled-standalone summary
/// — gradient surface, big Available figure, Total/Used stat row, and a
/// zoned (0% Good · High · Over Limit · 100%) progress bar with an animated
/// percent read-out.
class _LimitSummaryCard extends StatelessWidget {
  const _LimitSummaryCard({
    required this.title,
    required this.totalLimit,
    required this.available,
    required this.used,
    required this.ratio,
    this.gradientColors,
  });

  static const List<Color> _defaultGradient = [Color(0xFF1A0B2E), Color(0xFF3B1F5C)];

  final String title;
  final double totalLimit;
  final double available;
  final double used;
  final double ratio;
  final List<Color>? gradientColors;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(AppSizes.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors ?? _defaultGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: AppShadows.soft(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_rounded, size: AppSizes.iconSm, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: AppSizes.xs),
                  Expanded(
                    child: Text(
                      title,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Available Credit',
                style: context.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 2),
              CountUpText(
                value: available,
                formatter: CurrencyFormatter.instance.format,
                style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(child: _HeroStat(label: 'Total Limit', value: totalLimit)),
                  Expanded(child: _HeroStat(label: 'Used', value: used)),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              _ZonedUtilizationBar(ratio: ratio),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
        const SizedBox(height: 2),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// The "0% · Good · High · Over Limit · 100%" zoned progress bar from the
/// reference design — an animated fill plus a percent readout above it, and
/// three zone labels below so the number always reads with context instead
/// of a bare percentage.
class _ZonedUtilizationBar extends StatelessWidget {
  const _ZonedUtilizationBar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${ratio.asPercent} used',
              style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => LinearProgressIndicator(
              value: animated,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0%', style: context.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            Text(
              'Good',
              style: context.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
            ),
            Text(
              'High',
              style: context.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
            ),
            Text(
              '100%',
              style: context.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The flat "All Cards (n)" list — one scannable row per physical card
/// (mini card-face art, shared-limit role badge if any, statement/due
/// dates, Available figure), with a status filter dropdown. Replaces the
/// old wallet-stack + separate linked-cards-row duplication with a single
/// consistent list of every card a user has.
class _AllCardsSection extends StatefulWidget {
  const _AllCardsSection({
    required this.cards,
    required this.accountNameById,
    required this.accountBankIdById,
    required this.accountColorById,
    required this.roleLabelById,
  });

  final List<CreditCardProfile> cards;
  final Map<String, String> accountNameById;
  final Map<String, String?> accountBankIdById;
  final Map<String, int> accountColorById;
  final Map<String, String> roleLabelById;

  @override
  State<_AllCardsSection> createState() => _AllCardsSectionState();
}

class _AllCardsSectionState extends State<_AllCardsSection> {
  CreditCardStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == null ? widget.cards : widget.cards.where((c) => c.status == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'All Cards (${filtered.length})',
                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            _StatusFilterDropdown(value: _filter, onChanged: (value) => setState(() => _filter = value)),
          ],
        ),
        const SizedBox(height: AppSizes.xs),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.xl),
            child: Center(
              child: Text(
                'No cards match this filter.',
                style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          )
        else
          Material(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: AppSizes.lg, endIndent: AppSizes.lg, color: context.colors.outlineVariant),
                  _CardListTile(
                    card: filtered[i],
                    name: widget.accountNameById[filtered[i].accountId] ?? 'Card',
                    bankId: widget.accountBankIdById[filtered[i].accountId],
                    colorValue: widget.accountColorById[filtered[i].accountId],
                    roleLabel: widget.roleLabelById[filtered[i].id],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// "All Cards ▾" — filters the list below by [CreditCardStatus]. Only
/// statuses this app actually tracks; there is no invented "favorite" or
/// "recently used" filter here.
class _StatusFilterDropdown extends StatelessWidget {
  const _StatusFilterDropdown({required this.value, required this.onChanged});

  final CreditCardStatus? value;
  final ValueChanged<CreditCardStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.primaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<CreditCardStatus?>(
        initialValue: value,
        onSelected: onChanged,
        padding: EdgeInsets.zero,
        itemBuilder: (context) => [
          const PopupMenuItem(value: null, child: Text('All Cards')),
          for (final status in CreditCardStatus.values) PopupMenuItem(value: status, child: Text(status.label)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value?.label ?? 'All Cards',
                style: context.textTheme.labelLarge?.copyWith(
                  color: context.colors.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, color: context.colors.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardListTile extends ConsumerWidget {
  const _CardListTile({required this.card, required this.name, this.bankId, this.colorValue, this.roleLabel});

  final CreditCardProfile card;
  final String name;
  final String? bankId;
  final int? colorValue;

  /// "Primary/Secondary/Additional Card" when this card shares a limit with
  /// siblings — see [_sharedLimitRoleLabels]. Null for a standalone card.
  final String? roleLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(creditCardStandingProvider(card.id));
    final nextDue = ref
        .watch(statementsWithLiveTotalsProvider(card.id))
        .where((s) => s.remainingAmount > 0)
        .fold<DateTime?>(null, (soonest, s) => soonest == null || s.dueDate.isBefore(soonest) ? s.dueDate : soonest);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('${AppRoutes.creditCards}/${card.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 52,
                child: _CardListThumbnail(
                  colorValue: colorValue ?? context.colors.primary.toARGB32(),
                  bankId: bankId,
                  lastFourDigits: card.lastFourDigits,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (roleLabel != null || !card.status.isActive)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.xs),
                        child: Wrap(
                          spacing: AppSizes.xs,
                          runSpacing: AppSizes.xs,
                          children: [
                            if (roleLabel != null) _RoleBadge(label: roleLabel!),
                            if (!card.status.isActive) _StatusPill(status: card.status),
                          ],
                        ),
                      ),
                    Text(
                      name,
                      style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due ${_dueLabel(nextDue)}',
                      style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Available',
                      style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.instance.format(standing.available),
                      style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _CardMenu(card: card, name: name),
            ],
          ),
        ),
      ),
    );
  }

  static String _dueLabel(DateTime? date) {
    if (date == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

/// "Primary/Secondary/Additional Card" chip — same visual language as
/// [_StatusPill] but on the theme's primary tint, since a role isn't a
/// health signal the way a status is.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A square (no rounding), gradient card-face thumbnail for the "All Cards"
/// list row — the bank's full name (no logo assets are shipped in this app)
/// plus the masked last-4 digits. Purpose-built rather than reusing
/// [CreditCardVisual.compact]: that variant also fits a network wordmark
/// and repeats the account name, which at this row's narrow width left no
/// room for the digits themselves.
class _CardListThumbnail extends StatelessWidget {
  const _CardListThumbnail({required this.colorValue, this.bankId, this.lastFourDigits});

  final int colorValue;
  final String? bankId;
  final String? lastFourDigits;

  @override
  Widget build(BuildContext context) {
    final base = Color(colorValue);
    final bankName = BankRegistry.byId(bankId)?.name;
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, 0.4)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (bankName != null)
            Text(
              bankName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10, height: 1.15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            lastFourDigits != null && lastFourDigits!.isNotEmpty ? '•••• $lastFourDigits' : '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }
}

/// The per-card overflow menu — View Statement / View Transactions / Edit
/// Card / Deactivate Card / Delete Card, each scoped to this one physical
/// card only. "Deactivate" maps onto the existing [CreditCardStatus.blocked]
/// state (temporarily unusable, reversible); "Delete" soft-deletes the
/// linked Account (a card IS an account), with a trash/undo safety net.
/// Actions act on that one card alone — its siblings under the same shared
/// limit are untouched.
class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.card, required this.name});

  final CreditCardProfile card;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: AppSizes.iconSm,
        color: context.colors.onSurface.withValues(alpha: 0.6),
      ),
      padding: EdgeInsets.zero,
      onSelected: (value) async {
        switch (value) {
          case 'statement':
            context.push('${AppRoutes.creditCards}/${card.id}');
          case 'transactions':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TransactionsScreen(initialAccountId: card.accountId)),
            );
          case 'edit':
            CreditCardFormSheet.show(context, card: card);
          case 'deactivate':
            await ref.read(creditCardRepositoryProvider).editCard(card, status: CreditCardStatus.blocked);
          case 'activate':
            await ref.read(creditCardRepositoryProvider).editCard(card, status: CreditCardStatus.active);
          case 'delete':
            await _deleteCard(context, ref, card, name);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'statement',
          child: ListTile(
            leading: Icon(Icons.receipt_long_outlined),
            title: Text('View statement'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'transactions',
          child: ListTile(
            leading: Icon(Icons.receipt_outlined),
            title: Text('View transactions'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit card'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (card.status.isActive)
          const PopupMenuItem(
            value: 'deactivate',
            child: ListTile(
              leading: Icon(Icons.block_rounded),
              title: Text('Deactivate card'),
              contentPadding: EdgeInsets.zero,
            ),
          )
        else
          const PopupMenuItem(
            value: 'activate',
            child: ListTile(
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('Reactivate card'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
            title: Text('Delete card', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Confirms, then soft-deletes the [Account] backing [card] — a card IS an
/// account, so removing a card is removing that account (with the same
/// trash/undo safety net every other account gets).
Future<void> _deleteCard(BuildContext context, WidgetRef ref, CreditCardProfile card, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete card?'),
      content: Text('"$name" will be moved to trash. Its transactions and statements are kept.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final accounts = ref.read(accountsStreamProvider).value ?? const [];
  final account = accounts.where((a) => a.id == card.accountId).firstOrNull;
  if (account == null) return;

  final accountRepository = ref.read(accountRepositoryProvider);
  await accountRepository.softDelete(account);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$name moved to trash'),
      action: SnackBarAction(label: 'Undo', onPressed: () => accountRepository.restore(account)),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

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
