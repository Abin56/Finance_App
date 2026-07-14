import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../domain/person.dart';

/// Shares a plain payment-request message via the platform's native share
/// sheet (WhatsApp/SMS/Email) — this app has no messaging integration of
/// its own, so "Request" hands the wording off the same way
/// [ShareStatement] hands off the full statement text.
abstract class RequestPayment {
  RequestPayment._();

  static String buildText(Person person) {
    final amount = CurrencyFormatter.instance.format(person.currentBalance.abs());
    return 'Hi ${person.name}, just a reminder that you owe me $amount. Could you send it over when you get a chance?';
  }

  static Future<void> send(Person person) {
    return SharePlus.instance.share(ShareParams(text: buildText(person), subject: 'Payment reminder'));
  }
}
