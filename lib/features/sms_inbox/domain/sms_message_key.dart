import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Identifies one *physical* SMS on the device, as opposed to
/// [SmsDedupKey], which identifies one *financial event*.
///
/// The two are deliberately different strengths, and the SMS Inbox needs
/// both:
///
///  * [SmsMessageKey] is exact — raw sender, exact timestamp, exact body.
///    It backs the `UNIQUE(message_key)` column, which is what makes
///    re-scanning the device inbox idempotent: the same physical message
///    re-read on every scan is recognized and skipped, never re-inserted.
///  * `SmsDedupKey` is deliberately coarser — it normalizes the sender's DLT
///    prefix and prefers the reference number over the body. Two *different*
///    physical messages describing the *same* payment (a bank re-sending it
///    from `AX-HDFCBK` after `VM-HDFCBK`, or with different trailing promo
///    text) therefore share a dedup key while having distinct message keys.
///
/// That gap is exactly the duplicate set the Duplicates filter reviews. The
/// device SMS API exposes no stable per-message id to use instead, and two
/// messages with byte-identical sender, timestamp and body are
/// indistinguishable in principle — so collapsing those is correct, not a
/// lossy shortcut.
abstract class SmsMessageKey {
  SmsMessageKey._();

  static String compute({required String sender, required DateTime dateTime, required String body}) {
    final raw = '$sender|${dateTime.millisecondsSinceEpoch}|$body';
    return sha256.convert(utf8.encode(raw)).toString();
  }
}
