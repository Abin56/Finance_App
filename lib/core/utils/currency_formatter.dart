import 'package:intl/intl.dart';

/// Formats amounts using the user's selected currency (default INR).
/// The active currency code is read from settings in later milestones;
/// for Milestone 1 this exposes a static default plus a configurable instance.
class CurrencyFormatter {
  CurrencyFormatter({String symbol = '₹', String locale = 'en_IN'})
      : _format = NumberFormat.currency(locale: locale, symbol: symbol, decimalDigits: 2);

  final NumberFormat _format;

  String format(num amount) => _format.format(amount);

  /// Compact form for tight spaces, e.g. "₹1.2K", "₹3.4M".
  String formatCompact(num amount) {
    final compact = NumberFormat.compactCurrency(
      locale: _format.locale,
      symbol: _format.currencySymbol,
    );
    return compact.format(amount);
  }

  static final CurrencyFormatter instance = CurrencyFormatter();
}
