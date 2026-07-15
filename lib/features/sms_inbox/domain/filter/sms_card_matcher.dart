import '../../../credit_cards/domain/credit_card_profile.dart';
import '../sms_inbox_item.dart';

/// Resolves which of the user's credit cards an SMS refers to, using the
/// last-4 the parser lifted out of the message body against
/// [CreditCardProfile.lastFourDigits].
///
/// It never guesses. A last-4 shared by two or more cards is treated as
/// unmatched rather than resolved to whichever card happens to come first —
/// a wrong card attribution here would quietly mis-file the user's spending.
/// (`SmsConversionRouter` takes `.firstOrNull` for its *prefill* suggestion,
/// where a wrong guess costs one visible tap to correct; a filter silently
/// hides rows instead, so it holds the stricter line.)
class SmsCardMatcher {
  const SmsCardMatcher._(this._cardIdByLastFour);

  /// Sentinel for "not confidently linked to any of your cards" — covers a
  /// message with no last-4 at all, a last-4 matching no card, and an
  /// ambiguous last-4.
  static const String unknownCardId = '__unknown_card__';

  final Map<String, String> _cardIdByLastFour;

  factory SmsCardMatcher.fromCards(Iterable<CreditCardProfile> cards) {
    final byLastFour = <String, String>{};
    final ambiguous = <String>{};

    for (final card in cards) {
      final lastFour = card.lastFourDigits;
      if (lastFour == null || lastFour.isEmpty) continue;
      if (byLastFour.containsKey(lastFour)) {
        ambiguous.add(lastFour);
        continue;
      }
      byLastFour[lastFour] = card.id;
    }
    byLastFour.removeWhere((lastFour, _) => ambiguous.contains(lastFour));

    return SmsCardMatcher._(byLastFour);
  }

  /// The card id this SMS belongs to, or [unknownCardId].
  String cardIdFor(SmsInboxItem item) {
    final lastFour = item.parsed?.maskedAccountOrCard;
    if (lastFour == null) return unknownCardId;
    return _cardIdByLastFour[lastFour] ?? unknownCardId;
  }

  /// Whether any card at all can be matched. Drives hiding the whole Card
  /// section when the user has no cards carrying a last-4 — an empty filter
  /// section is a filter that cannot produce meaningful results.
  bool get hasMatchableCards => _cardIdByLastFour.isNotEmpty;

  /// The cards a filter can actually offer: those with an unambiguous last-4.
  /// A card excluded here can never be returned by [cardIdFor], so offering
  /// it would be a filter guaranteed to match nothing.
  Set<String> get matchableCardIds => _cardIdByLastFour.values.toSet();
}
