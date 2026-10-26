import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';

/// Whole-rupee amounts — the Dashboard's at-a-glance precision (every card
/// used to build this same `NumberFormat` locally).
final NumberFormat _rupees = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String formatRupees(num amount) => _rupees.format(amount);

/// "₹1.2L"-style compact form for captions and tight trailing slots.
String formatRupeesCompact(num amount) =>
    CurrencyFormatter.instance.formatCompact(amount);
