import '../sms_inbox_item.dart';

/// Sort orders for the SMS Inbox feed. Ordering is presentation-only — it
/// never touches the stored rows or any converted record.
enum SmsSortOrder { newestFirst, oldestFirst, highestAmount, lowestAmount, alphabetical }

extension SmsSortOrderX on SmsSortOrder {
  String get label {
    switch (this) {
      case SmsSortOrder.newestFirst:
        return 'Newest first';
      case SmsSortOrder.oldestFirst:
        return 'Oldest first';
      case SmsSortOrder.highestAmount:
        return 'Highest amount';
      case SmsSortOrder.lowestAmount:
        return 'Lowest amount';
      case SmsSortOrder.alphabetical:
        return 'Alphabetical';
    }
  }

  /// Unparsed messages have no amount and no merchant. They sort last in the
  /// amount and alphabetical orders rather than being treated as ₹0/"" — a
  /// blank isn't a small value, and burying them under real rows would hide
  /// exactly the messages that still need a human to look at them.
  int compare(SmsInboxItem a, SmsInboxItem b) {
    switch (this) {
      case SmsSortOrder.newestFirst:
        return b.rawMessage.date.compareTo(a.rawMessage.date);
      case SmsSortOrder.oldestFirst:
        return a.rawMessage.date.compareTo(b.rawMessage.date);
      case SmsSortOrder.highestAmount:
        return _byAmount(a, b, descending: true);
      case SmsSortOrder.lowestAmount:
        return _byAmount(a, b, descending: false);
      case SmsSortOrder.alphabetical:
        return _byName(a, b);
    }
  }

  int _byAmount(SmsInboxItem a, SmsInboxItem b, {required bool descending}) {
    final left = a.parsed?.amount;
    final right = b.parsed?.amount;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return descending ? right.compareTo(left) : left.compareTo(right);
  }

  int _byName(SmsInboxItem a, SmsInboxItem b) {
    final left = a.parsed?.merchantOrSender ?? a.rawMessage.address;
    final right = b.parsed?.merchantOrSender ?? b.rawMessage.address;
    return left.toLowerCase().compareTo(right.toLowerCase());
  }
}
