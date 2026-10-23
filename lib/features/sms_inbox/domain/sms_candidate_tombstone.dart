import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/smsCandidateTombstones/{smsItemId}` — durable "handled"
/// marker for an SMS transaction candidate, written by the web app at the
/// same moment it deletes the candidate document on import or dismiss.
///
/// Same document id as the candidate it replaces — 1:1 by construction, no
/// separate id scheme. See `docs/sms-background-cloud-sync-architecture.md`
/// (§1) for the full design: the candidate collection has no status field,
/// so "existence == pending" alone gives Android no way to tell "never
/// synced" apart from "already handled," and would resurrect a handled
/// candidate on the next device sync.
///
/// PROPOSAL STATUS (2026-10-23): schema + rules only so far (Phase A).
/// Nothing reads or writes this collection from Android yet — the
/// transactional tombstone-check-then-upload path lands in Phase C/D.
/// `kSmsAutoSyncCloudUploadEnabled` stays `false` until then.
///
/// Immutable once written — `firestore.rules` denies `update` outright, so a
/// dismissed candidate's tombstone can never later be rewritten as imported
/// or vice versa. Android only ever reads this; nothing deletes a tombstone
/// in the current design (kept indefinitely for now, revisit later).
enum SmsCandidateTombstoneOutcome {
  imported,
  dismissed;

  static SmsCandidateTombstoneOutcome? fromName(String? name) {
    for (final value in SmsCandidateTombstoneOutcome.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

class SmsCandidateTombstone {
  SmsCandidateTombstone({
    required this.smsItemId,
    required this.outcome,
    required this.handledAt,
    this.transactionId,
    this.source = 'web',
    this.schemaVersion = 1,
  });

  /// Same value as the candidate document id ([SmsTransactionCandidateCloud.smsItemId]) this replaces.
  final String smsItemId;

  final SmsCandidateTombstoneOutcome outcome;

  /// Set only when [outcome] is [SmsCandidateTombstoneOutcome.imported]; always `null` for `dismissed`.
  final String? transactionId;

  final DateTime handledAt;

  /// Literal `'web'` today — future-proofs against Android ever writing its own tombstones.
  final String source;

  final int schemaVersion;

  factory SmsCandidateTombstone.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    final outcome = SmsCandidateTombstoneOutcome.fromName(
      data['outcome'] as String?,
    );
    if (outcome == null) {
      throw StateError(
        'smsCandidateTombstones/${snapshot.id} has no valid outcome',
      );
    }
    return SmsCandidateTombstone(
      smsItemId: snapshot.id,
      outcome: outcome,
      transactionId: data['transactionId'] as String?,
      handledAt: (data['handledAt'] as Timestamp).toDate(),
      source: data['source'] as String? ?? 'web',
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 1,
    );
  }
}
