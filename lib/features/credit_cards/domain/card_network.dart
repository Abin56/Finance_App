import 'package:flutter/material.dart';

/// Which payment network a credit card runs on — display/filtering
/// metadata only, no effect on statement generation or payment logic.
enum CardNetwork { visa, mastercard, rupay, amex }

extension CardNetworkX on CardNetwork {
  static CardNetwork? fromName(String? name) {
    if (name == null) return null;
    return CardNetwork.values.where((n) => n.name == name).firstOrNull;
  }

  String get label {
    switch (this) {
      case CardNetwork.visa:
        return 'Visa';
      case CardNetwork.mastercard:
        return 'Mastercard';
      case CardNetwork.rupay:
        return 'RuPay';
      case CardNetwork.amex:
        return 'Amex';
    }
  }

  IconData get icon => Icons.credit_card_rounded;
}
