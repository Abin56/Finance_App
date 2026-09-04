import '../../features/accounts/domain/account.dart';
import '../../features/accounts/domain/account_type.dart';
import '../../features/credit_cards/domain/credit_card_profile.dart';
import '../models/bank_info.dart';

/// Computed display name for a bank-linked [Account] — "{shortCode} •
/// ****{last4}", or "{shortCode} Account" when no last 4 digits are on
/// file. Used in place of a manually-typed account name once a bank is
/// picked, since "SBI" + "Savings" + the last 4 digits already uniquely
/// identify the account without asking the user to type anything.
String bankAccountDisplayName({required BankInfo bank, String? last4}) {
  if (last4 != null && last4.isNotEmpty) return '${bank.shortCode} • ****$last4';
  return '${bank.shortCode} Account';
}

/// Computed display name for a credit card account — "{shortCode}
/// {network} • ****{last4}" (e.g. "HDFC Visa • ****5678"), degrading
/// gracefully as bank/network/last4 go unset down to a plain "Credit Card".
String cardDisplayName({BankInfo? bank, String? networkLabel, String? last4}) {
  final prefix = [
    if (bank != null) bank.shortCode,
    if (networkLabel != null && networkLabel.isNotEmpty) networkLabel,
  ].join(' ');
  final label = prefix.isEmpty ? 'Credit Card' : prefix;
  if (last4 != null && last4.isNotEmpty) return '$label **$last4';
  return label;
}

/// Label for [account] in an account/card picker (dropdown, chip, etc.) —
/// appends " **{lastFourDigits}" when [account] is a card-type account with
/// a linked [CreditCardProfile] that has last-4 digits on file and the
/// account name doesn't already include them, so otherwise-identically-named
/// cards (e.g. two accounts both named "Freedom") are distinguishable.
/// Every other account (cash, bank, wallet, business, other — or a card with
/// no digits set, or whose name already ends with those digits) falls back
/// to the plain [Account.name], unchanged. Distinct from [cardDisplayName]/
/// [bankAccountDisplayName]: those compute a name once at account-creation
/// time (baked into [Account.name]); this resolves live against the
/// account's *current* linked [CreditCardProfile] every time a picker
/// renders, so a card number added after the account was created/renamed
/// still shows up immediately.
String accountPickerLabel(Account account, List<CreditCardProfile> creditCards) {
  if (account.type != AccountType.card) return account.name;
  final card = creditCards.where((c) => c.accountId == account.id).firstOrNull;
  final last4 = card?.lastFourDigits;
  if (last4 == null || last4.isEmpty) return account.name;
  if (account.name.endsWith(last4)) return account.name;
  return '${account.name} **$last4';
}
