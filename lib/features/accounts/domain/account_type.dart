import 'package:flutter/material.dart';

/// The kind of account, used to pick an icon/label and to group dashboard
/// totals (cash vs bank vs business, etc.).
enum AccountType { cash, bank, card, wallet, business, other }

extension AccountTypeX on AccountType {
  static AccountType fromName(String name) =>
      AccountType.values.firstWhere((t) => t.name == name, orElse: () => AccountType.other);

  String get label {
    switch (this) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bank:
        return 'Bank Account';
      case AccountType.card:
        return 'Card';
      case AccountType.wallet:
        return 'Wallet';
      case AccountType.business:
        return 'Business';
      case AccountType.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case AccountType.cash:
        return Icons.payments_outlined;
      case AccountType.bank:
        return Icons.account_balance_outlined;
      case AccountType.card:
        return Icons.credit_card_outlined;
      case AccountType.wallet:
        return Icons.account_balance_wallet_outlined;
      case AccountType.business:
        return Icons.work_outline_rounded;
      case AccountType.other:
        return Icons.more_horiz_rounded;
    }
  }
}
