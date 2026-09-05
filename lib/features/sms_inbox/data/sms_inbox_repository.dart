import '../../../core/utils/id_generator.dart';
import '../domain/bank_sender_matcher.dart';
import '../domain/sms_dedup_key.dart';
import '../domain/sms_duplicate_reason.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_inbox_item.dart';
import '../domain/sms_message_key.dart';
import '../domain/sms_message_source.dart';
import '../domain/sms_parser.dart';
import '../domain/sms_parser_registry.dart';
import 'notification_capture_adapter.dart';
import 'sms_inbox_dao.dart';
import 'sms_reader_adapter.dart';

/// The SMS Inbox feature's real API surface. This class — and only this
/// class — is allowed to read the device SMS inbox/notifications and persist
/// SMS metadata; it depends solely on [SmsInboxDao] (local sqflite),
/// [SmsReaderAdapter] (device SMS) and [NotificationCaptureAdapter]
/// (notification-sourced captures, for messages like RCS alerts that never
/// reach `content://sms` at all), and deliberately imports nothing
/// Firestore-related. That is what structurally guarantees the feature's
/// privacy requirement: pending/ignored SMS data can never reach the cloud,
/// because nothing in this class has a path to Firestore. Only once the
/// user converts an item does a *different*, unchanged repository
/// (`TransactionRepository`, `ExpenseRepository`, etc.) create a normal
/// cloud record — see `SmsConversionRouter`.
class SmsInboxRepository {
  const SmsInboxRepository(
    this._dao,
    this._reader, {
    this.parserRegistry = const SmsParserRegistry(),
    this.notificationReader = const NotificationCaptureAdapter(),
  });

  final SmsInboxDao _dao;
  final SmsReaderAdapter _reader;
  final SmsParserRegistry parserRegistry;

  /// Supplementary source alongside [_reader] — captures notification text
  /// for RCS/other bank alerts that never reach `content://sms` at all. See
  /// [NotificationCaptureAdapter]'s doc comment.
  final NotificationCaptureAdapter notificationReader;

  /// Reads the device inbox, drops anything non-financial (OTP/promo/spam/
  /// delivery/recharge), parses the rest, and stores every genuinely new
  /// message. Returns the count of newly-discovered items.
  ///
  /// Safe to call repeatedly: a physical message already stored is recognized
  /// by its `UNIQUE(message_key)` and skipped, so re-scanning never
  /// re-imports or re-inserts anything. A physical message the user has
  /// since *deleted* is recognized the same way, via the tombstone
  /// [SmsInboxDao.deletedMessageKeysAmong] checks — so deleting an item
  /// (imported or not) stays deleted across future scans/app restarts
  /// instead of reappearing as a fresh pending row.
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
    final rawMessages = [
      ...await _reader.readInbox(),
      ...await notificationReader.readCaptured(),
    ];
    final items = <SmsInboxItem>[];

    // Tracks the dedup-key → original-item-id assignments made *within this
    // scan* (not yet committed to the DB) — so two duplicate messages that
    // both arrive in the same scan are still correctly linked to each
    // other, the same way the previous insert-per-message loop got this for
    // free from each insert being visible to the next iteration's DB query
    // before batching replaced it (see [SmsInboxDao.insertManyIfNew]).
    final originalIdByDedupKeyThisScan = <String, String>{};

    // Same rationale as [originalIdByDedupKeyThisScan], for the fuzzy
    // cross-source check below: a device-SMS message and its notification
    // counterpart typically arrive in the very same scan (the first scan
    // ever, or right after both land within moments of each other), and the
    // device-SMS row isn't committed to the DB until [SmsInboxDao.insertManyIfNew]
    // runs at the very end of this method — so a DB-only lookup would never
    // find it. [_reader]'s messages are always ordered before
    // [notificationReader]'s in [rawMessages], so every device-SMS item is
    // already in this list by the time a notification-sourced item is
    // processed.
    final deviceSmsRecordsThisScan = <_ScannedDeviceSms>[];

    final candidateKeys = rawMessages.map(
      (m) => SmsMessageKey.compute(
        sender: m.address,
        dateTime: m.date,
        body: m.body,
      ),
    );
    final deletedKeys = await _dao.deletedMessageKeysAmong(candidateKeys);

    for (final message in rawMessages) {
      if (!SmsFinancialFilter.isFinancial(message)) continue;

      final messageKey = SmsMessageKey.compute(
        sender: message.address,
        dateTime: message.date,
        body: message.body,
      );
      // Previously deleted by the user — re-reading the same physical device
      // message must never resurrect it (see [SmsInboxDao.deleteByIds]).
      if (deletedKeys.contains(messageKey)) continue;

      final parsed = parserRegistry.tryParse(message);
      final dedupKey = SmsDedupKey.compute(
        sender: message.address,
        dateTime: message.date,
        amount: parsed?.amount ?? 0.0,
        referenceNumber: parsed?.referenceNumber,
        body: message.body,
      );

      String? originalId;
      SmsDuplicateReason? duplicateReason;

      // A notification-sourced message (RCS, or a real SMS Google Messages
      // also notified for) doesn't share a clock with the device SMS
      // provider, so it can't rely on SmsDedupKey's exact-millisecond match
      // to find an existing device-SMS row describing the same payment —
      // see SmsInboxDao.findLikelyOriginalByFuzzyMatch's doc comment. Tried
      // first, and only for notification-sourced items: this never changes
      // behavior for device-SMS-vs-device-SMS comparisons, which still go
      // through the exact-hash path below exactly as before.
      if (message.source == SmsMessageSource.notification && parsed != null) {
        final normalizedSender = BankSenderMatcher.normalize(message.address);
        const fuzzyWindow = Duration(minutes: 5);

        for (final record in deviceSmsRecordsThisScan) {
          if (record.normalizedSender == normalizedSender &&
              record.amount == parsed.amount &&
              record.date.difference(message.date).abs() <= fuzzyWindow) {
            originalId = record.id;
            break;
          }
        }

        originalId ??= (await _dao.findLikelyOriginalByFuzzyMatch(
          normalizedSender: normalizedSender,
          amount: parsed.amount,
          around: message.date,
          windowMinutes: 5,
        ))?.id;

        if (originalId != null) {
          duplicateReason = SmsDuplicateReason.sameSenderAmountAndTime;
        }
      }

      if (originalId == null) {
        final storedOriginal = await _dao.findOriginalByDedupKey(dedupKey);
        originalId = storedOriginal?.id ?? originalIdByDedupKeyThisScan[dedupKey];
        if (originalId != null) {
          duplicateReason = _reasonFor(parsed?.referenceNumber);
        }
      }

      final item = SmsInboxItem(
        id: IdGenerator.generate(),
        messageKey: messageKey,
        rawMessage: message,
        parsed: parsed,
        dedupKey: dedupKey,
        duplicateOfId: originalId,
        duplicateReason: duplicateReason,
        status: SmsImportStatus.pending,
        createdAt: DateTime.now(),
      );
      items.add(item);

      // Only the earliest item for a given dedup key in this scan should be
      // remembered as "the original" for a later duplicate in the same
      // scan — mirrors findOriginalByDedupKey's own earliest-wins rule.
      if (originalId == null) {
        originalIdByDedupKeyThisScan[dedupKey] = item.id;
        if (message.source == SmsMessageSource.deviceSms && parsed != null) {
          deviceSmsRecordsThisScan.add(
            _ScannedDeviceSms(
              normalizedSender: BankSenderMatcher.normalize(message.address),
              amount: parsed.amount,
              date: message.date,
              id: item.id,
            ),
          );
        }
      }
    }

    return _dao.insertManyIfNew(items);
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

  Future<List<SmsInboxItem>> getByStatus(SmsImportStatus status) =>
      _dao.getByStatus(status);

  /// Marks [id] as imported and links it to the FlowFi record it became.
  /// Callers must only invoke this *after* the target record's own save
  /// call has genuinely succeeded — never optimistically before — so a
  /// failed save never falsely marks an SMS as imported.
  Future<void> markImported(
    String id, {
    required String linkedEntityId,
    String? linkedEntityRoute,
  }) {
    return _dao.updateStatus(
      id,
      status: SmsImportStatus.imported,
      linkedEntityId: linkedEntityId,
      linkedEntityRoute: linkedEntityRoute,
      importedAt: DateTime.now(),
    );
  }

  Future<void> markIgnored(String id) {
    return _dao.updateStatus(
      id,
      status: SmsImportStatus.ignored,
      ignoredAt: DateTime.now(),
    );
  }

  /// Batched equivalent of [markIgnored] for a multi-select "Ignore all".
  Future<void> markIgnoredMany(List<String> ids) {
    return _dao.updateStatusMany(
      ids,
      status: SmsImportStatus.ignored,
      ignoredAt: DateTime.now(),
    );
  }

  /// Moves an ignored item back to pending review, clearing the stale
  /// `ignoredAt` timestamp from the earlier ignore rather than leaving it
  /// behind on a now-pending row.
  Future<void> restore(String id) => _dao.updateStatus(
    id,
    status: SmsImportStatus.pending,
    clearIgnoredAt: true,
  );

  /// Un-flags a message the duplicate rules got wrong, returning it to the
  /// normal inbox. Purely a visibility change — no financial record exists
  /// for an unconverted SMS, so nothing recalculates.
  Future<void> clearDuplicateFlag(String id) => _dao.clearDuplicateFlag(id);

  Future<void> deleteMany(List<String> ids) => _dao.deleteByIds(ids);
}

/// An in-progress scan's own record of one non-duplicate device-SMS item,
/// kept purely so a notification-sourced item processed later in the *same*
/// scan can still find it as a fuzzy-match candidate — see
/// [SmsInboxRepository.scanInbox]'s `deviceSmsRecordsThisScan` doc comment.
class _ScannedDeviceSms {
  const _ScannedDeviceSms({
    required this.normalizedSender,
    required this.amount,
    required this.date,
    required this.id,
  });

  final String normalizedSender;
  final double amount;
  final DateTime date;
  final String id;
}
