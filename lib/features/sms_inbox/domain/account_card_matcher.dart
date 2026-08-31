import 'package:collection/collection.dart';

import '../../../core/data/bank_registry.dart';
import '../../accounts/domain/account.dart';
import '../../credit_cards/domain/credit_card_profile.dart';
import 'account_match_result.dart';
import 'parsed_sms_transaction.dart';

/// One account or card [AccountCardMatcher] can resolve an SMS against —
/// built once from the user's real [Account]/[CreditCardProfile] data, never
/// a second, parallel account system. A credit card is represented by its
/// own last-4 (`CreditCardProfile.lastFourDigits`) rather than its linked
/// account's, since the two can legitimately differ or be entered
/// independently.
class _MatchTarget {
  const _MatchTarget({required this.accountId, this.cardId, required this.lastFour, this.bankId, required this.label});

  final String accountId;
  final String? cardId;
  final String lastFour;
  final String? bankId;
  final String label;
}

/// Resolves which existing [Account] (optionally, a [CreditCardProfile]
/// extending one) a parsed SMS belongs to.
///
/// Matching last-4 digits is the only signal strong enough to auto-resolve —
/// mirrors the stricter half of `SmsCardMatcher`'s rule: a last-4 shared by
/// more than one account/card is treated as ambiguous rather than guessed.
/// A bank match with no last-4 to confirm it is surfaced only as a
/// suggestion in [AccountMatchResult.alternatives], never as a resolved
/// match — see [AccountMatchResult] for why a wrong attribution here would
/// quietly mis-file the user's spending.
class AccountCardMatcher {
  AccountCardMatcher._(this._targets);

  final List<_MatchTarget> _targets;

  factory AccountCardMatcher({required Iterable<Account> accounts, required Iterable<CreditCardProfile> cards}) {
    final accountList = accounts.toList();
    final cardAccountIds = <String>{};
    final targets = <_MatchTarget>[];

    for (final card in cards) {
      final lastFour = card.lastFourDigits?.trim();
      if (lastFour == null || lastFour.isEmpty) continue;
      cardAccountIds.add(card.accountId);

      final account = accountList.firstWhereOrNull((a) => a.id == card.accountId);
      targets.add(
        _MatchTarget(
          accountId: card.accountId,
          cardId: card.id,
          lastFour: lastFour,
          bankId: account?.bankId,
          label: account == null ? 'Card ••••$lastFour' : '${account.name} ••••$lastFour',
        ),
      );
    }

    // A plain account only contributes a target when it isn't already
    // represented via its CreditCardProfile above — otherwise the same
    // underlying account could appear twice under two different last-4s.
    for (final account in accountList) {
      if (cardAccountIds.contains(account.id)) continue;
      final lastFour = account.accountNumberLast4?.trim();
      if (lastFour == null || lastFour.isEmpty) continue;
      targets.add(
        _MatchTarget(accountId: account.id, lastFour: lastFour, bankId: account.bankId, label: '${account.name} ••••$lastFour'),
      );
    }

    return AccountCardMatcher._(targets);
  }

  AccountMatchResult match(ParsedSmsTransaction parsed) {
    final smsBankId = parsed.bankName == null ? null : BankRegistry.matchByName(parsed.bankName!)?.id;
    final lastFour = parsed.maskedAccountOrCard?.trim();

    if (lastFour != null && lastFour.isNotEmpty) {
      final byLastFour = _targets.where((t) => t.lastFour == lastFour).toList();

      if (byLastFour.length == 1) {
        final target = byLastFour.single;
        final bankConfirms = smsBankId != null && target.bankId == smsBankId;
        return AccountMatchResult(
          isResolved: true,
          matchedAccountId: target.accountId,
          matchedCardId: target.cardId,
          bankConfirmed: bankConfirms,
          matchReason: bankConfirms
              ? 'Matched ${target.label} by last-4 and bank.'
              : 'Matched ${target.label} by last-4.',
        );
      }

      if (byLastFour.length > 1) {
        return AccountMatchResult.unresolved(
          reason: 'Multiple accounts/cards share the last-4 digits ••••$lastFour — could not confidently pick one.',
          alternatives: byLastFour
              .map((t) => AccountMatchCandidate(accountId: t.accountId, cardId: t.cardId, reason: 'Shares last-4 ••••$lastFour'))
              .toList(),
        );
      }
    }

    // No last-4 (or it matched nothing) — a bank match alone is never
    // enough to auto-resolve, only to suggest.
    if (smsBankId != null) {
      final sameBank = _targets.where((t) => t.bankId == smsBankId).toList();
      if (sameBank.isNotEmpty) {
        return AccountMatchResult.unresolved(
          reason: sameBank.length == 1
              ? 'Matched ${sameBank.single.label} by bank only — no last-4 in the message to confirm.'
              : 'Matched ${parsed.bankName} but the message has no last-4 to pick between ${sameBank.length} accounts.',
          alternatives:
              sameBank.map((t) => AccountMatchCandidate(accountId: t.accountId, cardId: t.cardId, reason: 'Same bank')).toList(),
        );
      }
    }

    return const AccountMatchResult.unresolved(reason: 'No matching account or card found for this message.');
  }
}
