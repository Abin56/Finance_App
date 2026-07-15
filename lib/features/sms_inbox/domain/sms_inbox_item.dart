import 'parsed_sms_transaction.dart';
import 'raw_sms_message.dart';
import 'sms_duplicate_reason.dart';
import 'sms_import_status.dart';

/// The row-level aggregate the SMS Inbox UI renders — one per financial SMS
/// that has been scanned, stored only in the local `sms_inbox` sqflite
/// table (never Firestore) until the user converts it. A `null` [parsed]
/// means the message was recognized as financial-shaped (passed
/// `SmsParser.isFinancial`) but no parser could confidently extract its
/// fields — it's still shown, with every field blank/editable on Convert.
class SmsInboxItem {
  const SmsInboxItem({
    required this.id,
    required this.messageKey,
    required this.rawMessage,
    required this.dedupKey,
    required this.status,
    required this.createdAt,
    this.parsed,
    this.duplicateOfId,
    this.duplicateReason,
    this.linkedEntityId,
    this.linkedEntityRoute,
    this.importedAt,
    this.ignoredAt,
  });

  final String id;

  /// Identifies the physical device message — see `SmsMessageKey`. Unique per
  /// row, which is what makes re-scanning idempotent.
  final String messageKey;

  final RawSmsMessage rawMessage;
  final ParsedSmsTransaction? parsed;
  final String dedupKey;
  final SmsImportStatus status;

  /// Set when this message describes a financial event another stored message
  /// already describes; points at that original. Duplicates are kept rather
  /// than discarded at scan (silently dropping a user's data is not
  /// something this app does), but they are excluded from the default inbox
  /// feed and can only be reviewed via the Duplicates filter.
  ///
  /// A duplicate is still an ordinary [SmsInboxItem] and is *never* converted
  /// automatically or in bulk — it reaches a real financial record only if
  /// the user explicitly converts it from the Duplicates review, which is the
  /// rare "the bank really did charge me twice" case.
  final String? duplicateOfId;

  /// Which rule flagged [duplicateOfId] — shown to the reviewing user, never
  /// used as justification to act on their behalf.
  final SmsDuplicateReason? duplicateReason;

  bool get isDuplicate => duplicateOfId != null;

  /// Id of the FlowFi record this SMS was converted into (a `Transaction`,
  /// `Expense`, installment payment, etc.) — set only once, by
  /// `SmsInboxRepository.markImported`, right after that record's own save
  /// call has genuinely succeeded.
  final String? linkedEntityId;
  final String? linkedEntityRoute;
  final DateTime? importedAt;
  final DateTime? ignoredAt;
  final DateTime createdAt;

  SmsInboxItem copyWith({
    SmsImportStatus? status,
    String? linkedEntityId,
    String? linkedEntityRoute,
    DateTime? importedAt,
    DateTime? ignoredAt,
  }) {
    return SmsInboxItem(
      id: id,
      messageKey: messageKey,
      rawMessage: rawMessage,
      parsed: parsed,
      dedupKey: dedupKey,
      duplicateOfId: duplicateOfId,
      duplicateReason: duplicateReason,
      status: status ?? this.status,
      createdAt: createdAt,
      linkedEntityId: linkedEntityId ?? this.linkedEntityId,
      linkedEntityRoute: linkedEntityRoute ?? this.linkedEntityRoute,
      importedAt: importedAt ?? this.importedAt,
      ignoredAt: ignoredAt ?? this.ignoredAt,
    );
  }
}
