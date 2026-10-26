import 'sms_inbox_item.dart';
import 'sms_import_status.dart';

/// Read-only breakdown of the pending, non-duplicate SMS rows by how their
/// `capturedForUid` relates to the account signed in right now. Counts only —
/// no uid, sender or message content ever leaves this function. Nothing is
/// rebound or written.
class SmsOwnershipSummary {
  const SmsOwnershipSummary({
    required this.matching,
    required this.missing,
    required this.mismatching,
  });

  /// Bound to the signed-in account: eligible for cloud upload.
  final int matching;

  /// Not bound to any account (legacy rows, or older than the sign-in).
  final int missing;

  /// Bound to a different account.
  final int mismatching;

  int get total => matching + missing + mismatching;
}

/// [currentUid] `null` (nobody signed in) means no row can match, so every
/// bound row counts as mismatching and every unbound row as missing.
SmsOwnershipSummary summarizeSmsOwnership(
  Iterable<SmsInboxItem> items,
  String? currentUid,
) {
  var matching = 0;
  var missing = 0;
  var mismatching = 0;
  for (final item in items) {
    if (item.status != SmsImportStatus.pending || item.isDuplicate) continue;
    final owner = item.capturedForUid;
    if (owner == null) {
      missing++;
    } else if (currentUid != null && owner == currentUid) {
      matching++;
    } else {
      mismatching++;
    }
  }
  return SmsOwnershipSummary(
    matching: matching,
    missing: missing,
    mismatching: mismatching,
  );
}
