/// One account/card [AccountCardMatcher] considered but did not choose as
/// the resolved match — surfaced so a future review UI can offer "did you
/// mean" alternatives instead of forcing the user to search from scratch.
class AccountMatchCandidate {
  const AccountMatchCandidate({required this.accountId, this.cardId, required this.reason});

  final String accountId;

  /// Set when this candidate is a credit card (the card IS an account —
  /// [accountId] is `CreditCardProfile.accountId`, [cardId] is
  /// `CreditCardProfile.id`), mirroring how [AccountCardMatcher.match]
  /// resolves a chosen match.
  final String? cardId;

  final String reason;
}

/// The result of [AccountCardMatcher.match] — never just an id. A wrong
/// account attribution here would quietly mis-file the user's spending, so
/// every field exists to make the decision explainable and, when the matcher
/// declined to guess, reviewable.
class AccountMatchResult {
  const AccountMatchResult({
    required this.isResolved,
    required this.matchReason,
    this.matchedAccountId,
    this.matchedCardId,
    this.bankConfirmed = false,
    this.alternatives = const [],
  });

  /// No signal in the SMS matched anything the user has on file.
  const AccountMatchResult.unresolved({required String reason, List<AccountMatchCandidate> alternatives = const []})
      : this(isResolved: false, matchReason: reason, alternatives: alternatives);

  /// True only when exactly one account/card was confidently identified.
  /// [AccountCardMatcher] never sets this for an ambiguous or absent match —
  /// see its class doc.
  final bool isResolved;

  /// Set when [isResolved] and the match is a plain (non-card) account, or
  /// always set alongside [matchedCardId] when the match is a credit card
  /// (a card is 1:1 with its underlying [Account]).
  final String? matchedAccountId;

  /// Set only when the resolved match is a credit card.
  final String? matchedCardId;

  /// Whether the SMS's bank (resolved via `BankRegistry.matchByName`) agrees
  /// with [matchedAccountId]'s own bank, on top of the last-4 match — two
  /// independent signals agreeing is strictly more confident than the last-4
  /// alone, which [SmsConfidenceScorer] weighs accordingly. Never true when
  /// [isResolved] is false.
  final bool bankConfirmed;

  /// Human-readable justification shown to the reviewing user — e.g.
  /// "Matched HDFC Credit Card ••••1234 by last-4 and bank." or "Two cards
  /// share the last-4 digits 1234 — could not confidently pick one."
  final String matchReason;

  /// Other accounts/cards that shared a signal but weren't confidently
  /// chosen (e.g. an ambiguous last-4, or a same-bank account when no last-4
  /// was available at all) — for a future "pick the right one" review step.
  final List<AccountMatchCandidate> alternatives;
}
