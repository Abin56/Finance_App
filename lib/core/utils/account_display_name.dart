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
  if (last4 != null && last4.isNotEmpty) return '$label • ****$last4';
  return label;
}
