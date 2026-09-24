import '../../sms_inbox/domain/merchant/merchant_key.dart';
import '../../transactions/domain/transaction.dart';
import 'detected_transaction.dart';

/// Flags a [DetectedTransaction] as a possible duplicate of either:
///  1. a real, already-imported [Transaction] — the one comparison SMS
///     Inbox's own dedup logic doesn't do (it only compares incoming SMS
///     against previously-seen SMS, never against the `transactions`
///     collection itself), or
///  2. an earlier [DetectedTransaction] in the same batch — catches the same
///     transaction appearing twice because the user selected two
///     overlapping screenshots (or the same screenshot twice). This also
///     protects `SmartImportController.import()` mid-loop: the Firestore
///     transaction list it reads is a single snapshot taken before the
///     import loop starts, so a transaction created earlier *in that same
///     loop* would not otherwise show up as "existing" for a later row in
///     the same batch.
///
/// Never relies on exact string matching alone: two screenshots of the same
/// payment routinely disagree on exact merchant text ("SWIGGY" vs "SWIGGY
/// FOOD") and on amount formatting ("₹420" vs "₹420.00"), so this compares
/// on amount (rounded to paise), date (same day, ±1 to absorb timezone/
/// rounding slack) and normalized description overlap — reusing
/// `MerchantKey.normalize`, the same loose merchant-name normalizer SMS
/// Inbox's own category-learning already relies on, rather than inventing a
/// second fuzzy-matching scheme. This is a heuristic, not a certainty — two
/// genuinely separate same-day, same-amount, same-merchant transactions
/// (e.g. two ₹420 Swiggy orders) will also match. That's an accepted
/// trade-off: the user only ever sees a "possible duplicate" warning with
/// Skip/Import-anyway, so a false positive costs one extra tap, never lost
/// data — see the module docs for why erring towards over-warning here is
/// preferable to erring towards missed real duplicates.
abstract class ScreenshotDuplicateDetector {
  ScreenshotDuplicateDetector._();

  /// Mutates [detected] in place, setting `isDuplicate`/`duplicateTransactionId`/
  /// `duplicateReason` and, for a newly-flagged duplicate, unchecking
  /// `isSelected` so importing it requires the user to explicitly override
  /// the warning. [accountId], when given, restricts the *existing-Transaction*
  /// comparison to that account only (within-batch comparisons are always
  /// checked regardless of account, since two rows in the same review batch
  /// share whichever account the user eventually picks); omit it to check
  /// across every account (the safer default before an account has been
  /// chosen on the review screen).
  static void apply(
    List<DetectedTransaction> detected,
    List<Transaction> existing, {
    String? accountId,
  }) {
    final candidates = accountId == null
        ? existing
        : existing.where((t) => t.accountId == accountId).toList();

    for (var i = 0; i < detected.length; i++) {
      final row = detected[i];
      final existingMatch = _findExistingMatch(row, candidates);
      // Only rows *earlier* in the batch are eligible matches, so the first
      // occurrence of a transaction is always the "clean" one and only
      // later repeats get flagged — otherwise two mutually-matching rows
      // would flag each other and there'd be no unambiguous original left.
      final batchMatch = existingMatch == null
          ? _findBatchMatch(row, detected.sublist(0, i))
          : null;

      if (existingMatch == null && batchMatch == null) {
        row.isDuplicate = false;
        row.duplicateTransactionId = null;
        row.duplicateReason = null;
        row.duplicateAcknowledged = false;
        continue;
      }

      row.isDuplicate = true;
      if (existingMatch != null) {
        row.duplicateTransactionId = existingMatch.id;
        row.duplicateReason =
            'Already recorded on ${_formatDate(existingMatch.dateTime)} for ₹${existingMatch.amount.toStringAsFixed(2)}';
      } else {
        // A within-batch match has no real Transaction id to point to.
        row.duplicateTransactionId = null;
        row.duplicateReason =
            'This looks the same as another transaction detected from your screenshots.';
      }
      // Only forces the row off on first detection — an explicit "Import
      // anyway" override must survive a re-check that still finds the same
      // kind of match, or the user's choice would be silently undone the
      // next time duplicates are recomputed (e.g. after an edit).
      if (!row.duplicateAcknowledged) {
        row.isSelected = false;
      }
    }
  }

  static Transaction? _findExistingMatch(
    DetectedTransaction row,
    List<Transaction> candidates,
  ) {
    if (row.date == null || row.amount == null) return null;

    final rowKey = MerchantKey.normalize(row.rawDescription);
    for (final candidate in candidates) {
      if (!_sameAmount(row.amount!, candidate.amount)) continue;
      if (!_withinOneDay(row.date!, candidate.dateTime)) continue;
      if (!_descriptionKeysOverlap(
        rowKey,
        MerchantKey.normalize(candidate.description),
      )) {
        continue;
      }
      return candidate;
    }
    return null;
  }

  static DetectedTransaction? _findBatchMatch(
    DetectedTransaction row,
    List<DetectedTransaction> earlierRows,
  ) {
    if (row.date == null || row.amount == null) return null;

    final rowKey = MerchantKey.normalize(row.rawDescription);
    for (final other in earlierRows) {
      if (other.date == null || other.amount == null) continue;
      if (!_sameAmount(row.amount!, other.amount!)) continue;
      if (!_withinOneDay(row.date!, other.date!)) continue;
      if (!_descriptionKeysOverlap(
        rowKey,
        MerchantKey.normalize(other.rawDescription),
      )) {
        continue;
      }
      return other;
    }
    return null;
  }

  static bool _sameAmount(double a, double b) => (a - b).abs() < 0.01;

  static bool _withinOneDay(DateTime a, DateTime b) {
    final dayA = DateTime(a.year, a.month, a.day);
    final dayB = DateTime(b.year, b.month, b.day);
    return dayA.difference(dayB).inDays.abs() <= 1;
  }

  static bool _descriptionKeysOverlap(String? rowKey, String? candidateKey) {
    if (rowKey == null || candidateKey == null) {
      // Neither side has an identifiable merchant token — amount + date
      // alone is treated as enough of a signal to warn, not enough to hide
      // the possibility from the user.
      return true;
    }
    if (rowKey == candidateKey) return true;
    final rowTokens = rowKey.split(' ').toSet();
    final candidateTokens = candidateKey.split(' ').toSet();
    return rowTokens.any(candidateTokens.contains);
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}
