import '../../../core/utils/id_generator.dart';
import '../domain/sms_dedup_key.dart';
import '../domain/sms_duplicate_reason.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_inbox_item.dart';
import '../domain/sms_message_key.dart';
import '../domain/sms_parser.dart';
import '../domain/sms_parser_registry.dart';
import 'sms_inbox_dao.dart';
import 'sms_reader_adapter.dart';

/// The SMS Inbox feature's real API surface. This class — and only this
/// class — is allowed to read the device SMS inbox and persist SMS
/// metadata; it depends solely on [SmsInboxDao] (local sqflite) and
/// [SmsReaderAdapter] (device SMS), and deliberately imports nothing
/// Firestore-related. That is what structurally guarantees the feature's
/// privacy requirement: pending/ignored SMS data can never reach the cloud,
/// because nothing in this class has a path to Firestore. Only once the
/// user converts an item does a *different*, unchanged repository
/// (`TransactionRepository`, `ExpenseRepository`, etc.) create a normal
/// cloud record — see `SmsConversionRouter`.
class SmsInboxRepository {
  const SmsInboxRepository(this._dao, this._reader, {this.parserRegistry = const SmsParserRegistry()});

  final SmsInboxDao _dao;
  final SmsReaderAdapter _reader;
  final SmsParserRegistry parserRegistry;

  /// Reads the device inbox, drops anything non-financial (OTP/promo/spam/
  /// delivery/recharge), parses the rest, and stores every genuinely new
  /// message. Returns the count of newly-discovered items.
  ///
  /// Safe to call repeatedly: a physical message already stored is recognized
  /// by its `UNIQUE(message_key)` and skipped, so re-scanning never
  /// re-imports or re-inserts anything.
  ///
  /// A *different* physical message describing a payment already stored (a
  /// bank re-sending it from another DLT sender, or with different promo
  /// text) is a genuine duplicate. It is stored and flagged against its
  /// original rather than discarded — the user's data is never silently
  /// dropped. Flagged duplicates are excluded from the default inbox feed
  /// (see `SmsFilterCriteria`) and are never converted automatically or in
  /// bulk, so they cannot reach Dashboard, History, Reports, Cash Flow or any
  /// balance unless the user explicitly converts one from the Duplicates
  /// review.
  Future<int> scanInbox() async {
    final rawMessages = await _reader.readInbox();
    var newCount = 0;

    for (final message in rawMessages) {
      if (!SmsFinancialFilter.isFinancial(message)) continue;

      final parsed = parserRegistry.tryParse(message);
      final dedupKey = SmsDedupKey.compute(
        sender: message.address,
        dateTime: message.date,
        amount: parsed?.amount ?? 0.0,
        referenceNumber: parsed?.referenceNumber,
        body: message.body,
      );

      final original = await _dao.findOriginalByDedupKey(dedupKey);

      final item = SmsInboxItem(
        id: IdGenerator.generate(),
        messageKey: SmsMessageKey.compute(
          sender: message.address,
          dateTime: message.date,
          body: message.body,
        ),
        rawMessage: message,
        parsed: parsed,
        dedupKey: dedupKey,
        duplicateOfId: original?.id,
        duplicateReason: original == null ? null : _reasonFor(parsed?.referenceNumber),
        status: SmsImportStatus.pending,
        createdAt: DateTime.now(),
      );

      final inserted = await _dao.insertIfNew(item);
      if (inserted) newCount++;
    }

    return newCount;
  }

  /// A shared reference number is what `SmsDedupKey` prefers when present, so
  /// its presence is exactly what distinguishes the two detection rules the
  /// Duplicates review shows the user.
  SmsDuplicateReason _reasonFor(String? referenceNumber) {
    return referenceNumber != null
        ? SmsDuplicateReason.sameReferenceNumber
        : SmsDuplicateReason.sameSenderAmountAndTime;
  }

  Future<List<SmsInboxItem>> getAll() => _dao.getAll();

  Future<List<SmsInboxItem>> getByStatus(SmsImportStatus status) => _dao.getByStatus(status);

  /// Marks [id] as imported and links it to the FlowFi record it became.
  /// Callers must only invoke this *after* the target record's own save
  /// call has genuinely succeeded — never optimistically before — so a
  /// failed save never falsely marks an SMS as imported.
  Future<void> markImported(String id, {required String linkedEntityId, String? linkedEntityRoute}) {
    return _dao.updateStatus(
      id,
      status: SmsImportStatus.imported,
      linkedEntityId: linkedEntityId,
      linkedEntityRoute: linkedEntityRoute,
      importedAt: DateTime.now(),
    );
  }

  Future<void> markIgnored(String id) {
    return _dao.updateStatus(id, status: SmsImportStatus.ignored, ignoredAt: DateTime.now());
  }

  /// Batched equivalent of [markIgnored] for a multi-select "Ignore all".
  Future<void> markIgnoredMany(List<String> ids) {
    return _dao.updateStatusMany(ids, status: SmsImportStatus.ignored, ignoredAt: DateTime.now());
  }

  /// Moves an ignored item back to pending review.
  Future<void> restore(String id) => _dao.updateStatus(id, status: SmsImportStatus.pending);

  /// Un-flags a message the duplicate rules got wrong, returning it to the
  /// normal inbox. Purely a visibility change — no financial record exists
  /// for an unconverted SMS, so nothing recalculates.
  Future<void> clearDuplicateFlag(String id) => _dao.clearDuplicateFlag(id);

  Future<void> deleteMany(List<String> ids) => _dao.deleteByIds(ids);
}
