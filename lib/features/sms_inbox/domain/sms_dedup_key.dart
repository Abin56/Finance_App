import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bank_sender_matcher.dart';

/// Computes the deterministic key `SmsInboxRepository` uses (via a
/// `UNIQUE` sqflite column) to guarantee the same SMS is never imported
/// twice — matched on sender + timestamp + amount + reference/transaction
/// id, per the feature spec.
abstract class SmsDedupKey {
  SmsDedupKey._();

  static String compute({
    required String sender,
    required DateTime dateTime,
    required double amount,
    String? referenceNumber,
    required String body,
  }) {
    final normalizedSender = BankSenderMatcher.normalize(sender);
    // A real reference/transaction number is the strongest duplicate
    // signal — banks often vary trailing promotional text between
    // otherwise-identical messages. Fall back to the trimmed body only
    // when no reference number was parseable.
    final referenceOrBody = referenceNumber ?? body.trim();
    final raw = '$normalizedSender|${dateTime.millisecondsSinceEpoch}|${amount.toStringAsFixed(2)}|$referenceOrBody';
    return sha256.convert(utf8.encode(raw)).toString();
  }
}
