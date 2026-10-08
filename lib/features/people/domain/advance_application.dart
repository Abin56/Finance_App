import 'package:cloud_firestore/cloud_firestore.dart';

/// Applying part of a person's advance (a `sourceKind: 'advance'` settlement
/// entry) to one obligation — `users/{uid}/people/{personId}/advanceApplications`.
/// Same document shape as the web app's `AdvanceApplication`. It moves neither
/// cash nor the person's balance (the advance already moved both when it was
/// received): it only says which obligation that money now settles.
class AdvanceApplication {
  AdvanceApplication({
    required this.id,
    required this.personId,
    required this.advanceEntryId,
    required this.obligationKey,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String personId;
  final String advanceEntryId;

  /// Statement key of the obligation — `ledger:{id}`, `emi-inst:{id}`.
  final String obligationKey;
  final double amount;
  final DateTime date;
  final DateTime createdAt;
  DateTime? deletedAt;

  factory AdvanceApplication.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return AdvanceApplication(
      id: snapshot.id,
      personId: data['personId'] as String,
      advanceEntryId: data['advanceEntryId'] as String,
      obligationKey: data['obligationKey'] as String,
      amount: (data['amount'] as num).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'personId': personId,
        'advanceEntryId': advanceEntryId,
        'obligationKey': obligationKey,
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(createdAt),
        'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      };
}
