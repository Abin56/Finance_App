/// Form field validators shared across add/edit screens for income,
/// expense, people, and bills.
abstract class Validators {
  Validators._();

  static String? required(String? value, {String message = 'This field is required'}) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String? amount(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter an amount';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number';
    if (parsed <= 0) return 'Amount must be greater than 0';
    return null;
  }

  /// Same as [amount], plus rejects an amount greater than [max] (e.g. a
  /// payment exceeding an obligation's remaining balance) — the one
  /// validator every "record a payment" sheet (EMI, Loan, Bill, Credit
  /// Card statement) should use instead of the plain [amount] check, so
  /// overpayment is rejected in the UI rather than silently clamped only
  /// in the repository's cached total.
  static String? Function(String?) amountUpTo(double max) {
    return (value) {
      final baseError = amount(value);
      if (baseError != null) return baseError;
      final parsed = double.parse(value!.trim());
      if (parsed > max) return 'Payment amount cannot exceed the remaining balance.';
      return null;
    };
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional field
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 7) return 'Enter a valid phone number';
    return null;
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional field
    if (!_emailPattern.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  /// For fields that may legitimately be negative (e.g. a person's opening
  /// balance can start negative if you already owed them) — only rejects
  /// blank/non-numeric input, unlike [amount] which also requires > 0.
  static String? signedAmount(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter an amount';
    if (double.tryParse(value.trim()) == null) return 'Enter a valid number';
    return null;
  }
}
