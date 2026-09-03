/// What kind of counterparty a resolved merchant identity represents —
/// deliberately separate from *category* (see [MerchantIdentity]'s class
/// doc): knowing a transaction is with "Amazon" says nothing about whether
/// it was a Prime subscription, a grocery order, or general shopping, and
/// this enum exists purely to answer "who/what is this," not "what for."
enum MerchantType {
  /// A real, named business FlowFi recognizes (in
  /// [MerchantIntelligenceCatalog] or the user's own transaction history) —
  /// the only value that licenses inventing a display name FlowFi didn't see
  /// verbatim in the message.
  knownBusiness,

  /// Explicit merchant-shaped text was present (a name, not a VPA/phone
  /// number) but it doesn't match anything FlowFi recognizes — e.g. "ABC
  /// Bakery" or "Ramesh Stores". The text is kept as-is; nothing about it is
  /// invented.
  unknownBusiness,

  /// The counterparty reads as a person's name (e.g. a P2P UPI payment to
  /// "Rohit Kumar") rather than a business — heuristic, not a guarantee; see
  /// [MerchantIdentityResolver]'s doc comment for the exact heuristic and its
  /// deliberate limits (never inferred from a bare phone number or VPA).
  individual,

  /// The counterparty is a bank itself (e.g. "transferred to SBI account") —
  /// signals a transfer, not a purchase; must not be forced into an expense
  /// category.
  bank,

  /// A UPI app / payment rail (PhonePe, Google Pay, Paytm, ...) mentioned in
  /// the message — see [UpiProvider]. Never the merchant itself; kept
  /// separate on [MerchantIdentity.paymentProvider] specifically so it can
  /// never be mistaken for one.
  paymentProvider,

  /// A government body or statutory payment (e.g. income tax, a municipal
  /// utility board run by the state) — reserved for catalog entries that are
  /// explicitly tagged as such; not inferred from wording alone.
  government,

  /// A recognized utility provider (electricity/water/gas/DTH/telecom) —
  /// distinguished from [subscription] since utilities are usually recurring
  /// necessities rather than optional services.
  utility,

  /// A recognized recurring-subscription business (streaming, SaaS, etc.).
  subscription,

  /// No usable signal at all — never a placeholder for "we didn't bother
  /// checking," only for "there was nothing to check."
  unknown,
}

extension MerchantTypeX on MerchantType {
  String get label {
    switch (this) {
      case MerchantType.knownBusiness:
        return 'Known business';
      case MerchantType.unknownBusiness:
        return 'Unrecognized business';
      case MerchantType.individual:
        return 'Individual';
      case MerchantType.bank:
        return 'Bank';
      case MerchantType.paymentProvider:
        return 'Payment provider';
      case MerchantType.government:
        return 'Government';
      case MerchantType.utility:
        return 'Utility';
      case MerchantType.subscription:
        return 'Subscription';
      case MerchantType.unknown:
        return 'Unknown';
    }
  }
}
