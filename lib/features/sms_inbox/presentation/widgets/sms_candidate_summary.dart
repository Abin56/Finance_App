import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/sms_confidence_scorer.dart';
import '../../domain/transaction_candidate.dart';
import '../providers/sms_inbox_providers.dart';

/// The account-match + confidence summary for one SMS's `TransactionCandidate`
/// (built by `TransactionCandidateBuilder` during the existing manual scan) —
/// shown in [SmsMessageDetailSheet] so the user can judge the suggestion
/// before converting. Purely informational: nothing here is ever applied
/// automatically, it only explains what [SmsConversionRouter] will pre-fill
/// if the user proceeds.
///
/// Renders nothing when no candidate exists yet for this SMS (unparsed
/// message, or a scan hasn't produced one yet) — the sheet's existing layout
/// is unaffected, exactly as before this feature existed.
class SmsCandidateSummary extends ConsumerWidget {
  const SmsCandidateSummary({super.key, required this.smsItemId});

  final String smsItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(transactionCandidatesProvider).valueOrNull ?? const [];
    final candidate = candidates.firstWhereOrNull((c) => c.smsItemId == smsItemId);
    if (candidate == null) return const SizedBox.shrink();

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
                  _accountLabel(ref, candidate),
                  style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              _ConfidenceBadge(level: candidate.confidenceLevel),
            ],
          ),
          if (candidate.needsReview && candidate.reviewReasons.isNotEmpty) ...[
            const SizedBox(height: AppSizes.xs),
            for (final reason in candidate.reviewReasons) _ReviewReasonRow(reason: reason),
          ],
        ],
      ),
    );
  }

  /// Resolves [TransactionCandidate.matchedAccountId]/[matchedCardId] into
  /// the same display name the rest of the app already uses for that
  /// account/card (e.g. `smsCardFilterOptionsProvider`'s "Name •••• 1234"),
  /// rather than inventing a second naming convention here.
  String _accountLabel(WidgetRef ref, TransactionCandidate candidate) {
    final accountId = candidate.matchedAccountId;
    if (accountId == null) return 'Account needs review';

    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final account = accounts.firstWhereOrNull((a) => a.id == accountId);
    if (account == null) return 'Account needs review';

    final cardId = candidate.matchedCardId;
    if (cardId != null) {
      final cards = ref.watch(activeCreditCardsProvider);
      final card = cards.firstWhereOrNull((c) => c.id == cardId);
      if (card?.lastFourDigits != null) return '${account.name} •••• ${card!.lastFourDigits}';
    }
    return account.name;
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
      child: Text(label, style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
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
          Icon(Icons.info_outline_rounded, size: AppSizes.iconSm, color: context.colors.onSurfaceVariant),
          const SizedBox(width: AppSizes.xs),
          Expanded(
            child: Text(reason, style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
