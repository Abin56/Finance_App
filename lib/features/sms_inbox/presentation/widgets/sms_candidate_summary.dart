import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/financial_event/financial_event.dart';
import '../../domain/financial_event/financial_event_type.dart';
import '../../domain/sms_confidence_scorer.dart';
import '../../domain/transaction_candidate.dart';
import '../providers/sms_inbox_providers.dart';

/// The account-match + confidence summary for one SMS — shown in
/// [SmsMessageDetailSheet] so the user can judge the suggestion before
/// converting. Purely informational: nothing here is ever applied
/// automatically, it only explains what [SmsConversionRouter] will pre-fill
/// if the user proceeds.
///
/// Prefers the new AI-hybrid `FinancialEvent` (see
/// `SmsInboxItemsNotifier._generateFinancialEventsForPending`) when one has
/// been linked to this SMS, falling back to the older `TransactionCandidate`
/// display for any SMS the new pipeline hasn't processed yet (e.g. one
/// scanned before this feature existed). Renders nothing when neither
/// exists — the sheet's existing layout is unaffected, exactly as before
/// this feature existed.
class SmsCandidateSummary extends ConsumerWidget {
  const SmsCandidateSummary({super.key, required this.smsItemId});

  final String smsItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref
        .watch(financialEventForSmsItemProvider(smsItemId))
        .valueOrNull;
    if (event != null) return _buildForEvent(context, ref, event);

    final candidates =
        ref.watch(transactionCandidatesProvider).valueOrNull ?? const [];
    final candidate = candidates.firstWhereOrNull(
      (c) => c.smsItemId == smsItemId,
    );
    if (candidate == null) return const SizedBox.shrink();
    return _buildForCandidate(context, ref, candidate);
  }

  Widget _buildForEvent(
    BuildContext context,
    WidgetRef ref,
    FinancialEvent event,
  ) {
    return _Card(
      accountLabel: _accountLabel(
        ref,
        event.accountMatch.value,
        event.matchedCardId,
      ),
      confidenceLevel: event.confidenceLevel,
      needsReview: event.needsReview,
      reviewReasons: event.reviewReasons,
      eventTypeLabel: event.eventType.label,
      subcategory: event.subcategory,
    );
  }

  Widget _buildForCandidate(
    BuildContext context,
    WidgetRef ref,
    TransactionCandidate candidate,
  ) {
    return _Card(
      accountLabel: _accountLabel(
        ref,
        candidate.matchedAccountId,
        candidate.matchedCardId,
      ),
      confidenceLevel: candidate.confidenceLevel,
      needsReview: candidate.needsReview,
      reviewReasons: candidate.reviewReasons,
    );
  }

  /// Resolves a matched account/card id pair into the same display name the
  /// rest of the app already uses (e.g. `smsCardFilterOptionsProvider`'s
  /// "Name •••• 1234"), rather than inventing a second naming convention.
  String _accountLabel(WidgetRef ref, String? accountId, String? cardId) {
    if (accountId == null) return 'Account needs review';

    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final account = accounts.firstWhereOrNull((a) => a.id == accountId);
    if (account == null) return 'Account needs review';

    if (cardId != null) {
      final cards = ref.watch(activeCreditCardsProvider);
      final card = cards.firstWhereOrNull((c) => c.id == cardId);
      if (card?.lastFourDigits != null)
        return '${account.name} •••• ${card!.lastFourDigits}';
    }
    return account.name;
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.accountLabel,
    required this.confidenceLevel,
    required this.needsReview,
    required this.reviewReasons,
    this.eventTypeLabel,
    this.subcategory,
  });

  final String accountLabel;
  final ConfidenceLevel confidenceLevel;
  final bool needsReview;
  final List<String> reviewReasons;

  /// Set only when this summary was built from a `FinancialEvent` — the
  /// AI-hybrid engine's reconciled read of what kind of event this is (e.g.
  /// "Payment", "Refund of an earlier charge"). Null for the older
  /// `TransactionCandidate` fallback, which has no equivalent concept.
  final String? eventTypeLabel;
  final String? subcategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  accountLabel,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              _ConfidenceBadge(level: confidenceLevel),
            ],
          ),
          if (eventTypeLabel != null) ...[
            const SizedBox(height: AppSizes.xs),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSizes.xs,
              children: [
                _EventTypeChip(label: eventTypeLabel!),
                if (subcategory != null)
                  Text(
                    subcategory!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
          if (needsReview && reviewReasons.isNotEmpty) ...[
            const SizedBox(height: AppSizes.xs),
            for (final reason in reviewReasons)
              _ReviewReasonRow(reason: reason),
          ],
        ],
      ),
    );
  }
}

class _EventTypeChip extends StatelessWidget {
  const _EventTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.level});

  final ConfidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (level) {
      ConfidenceLevel.high => (AppColors.success, 'High'),
      ConfidenceLevel.medium => (AppColors.warning, 'Medium'),
      ConfidenceLevel.low => (AppColors.error, 'Low'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReviewReasonRow extends StatelessWidget {
  const _ReviewReasonRow({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: AppSizes.iconSm,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSizes.xs),
          Expanded(
            child: Text(
              reason,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
