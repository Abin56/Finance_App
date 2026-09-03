/// The rail/app that moved the money — deliberately a separate concept from
/// the *merchant* (the counterparty being paid). "Paid ₹800 using PhonePe to
/// swiggy@upi" has [PaymentProvider.phonePe] as the provider and "Swiggy" as
/// the merchant; conflating the two would silently mislabel every UPI-app
/// transaction with the app's name instead of who was actually paid. See
/// [PaymentProviderResolver].
enum PaymentProvider {
  phonePe,
  googlePay,
  paytm,
  amazonPay,
  bhim,
  cred,
  whatsappPay,

  /// The message is a plain bank-rail transaction (NEFT/IMPS/card) with no
  /// third-party UPI app involved.
  bank,

  unknown,
}

extension PaymentProviderX on PaymentProvider {
  static PaymentProvider fromName(String? name) {
    if (name == null) return PaymentProvider.unknown;
    return PaymentProvider.values.firstWhere(
      (p) => p.name == name,
      orElse: () => PaymentProvider.unknown,
    );
  }

  String get label {
    switch (this) {
      case PaymentProvider.phonePe:
        return 'PhonePe';
      case PaymentProvider.googlePay:
        return 'Google Pay';
      case PaymentProvider.paytm:
        return 'Paytm';
      case PaymentProvider.amazonPay:
        return 'Amazon Pay';
      case PaymentProvider.bhim:
        return 'BHIM';
      case PaymentProvider.cred:
        return 'CRED';
      case PaymentProvider.whatsappPay:
        return 'WhatsApp Pay';
      case PaymentProvider.bank:
        return 'Bank';
      case PaymentProvider.unknown:
        return 'Unknown';
    }
  }
}
