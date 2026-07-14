import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// The detailed charge breakdown for one EMI payment — created only when a
/// payment is recorded through `RecordEmiPaymentSheet` (the EMI-specific
/// screen), never by Bills/Lending/split Expenses, which share the generic
/// `InstallmentPayment` this attaches to. Linked 1:1 by [paymentId], which
/// also doubles as this document's own id (see
/// `EmiPaymentBreakdownRepository`), so there's never more than one
/// breakdown per payment.
///
/// Only [principalPaid] ever restores a linked credit card's available
/// credit (see `principalRestoredForCardProvider`) — every other field here
/// (interest, GST, IGST, fees, penalties) is tracked for the user's records
/// only and never feeds back into the payment schedule or a card's limit.
class EmiPaymentBreakdown extends SoftDeletableEntity {
  EmiPaymentBreakdown({
    required this.id,
    required this.paymentId,
    required this.scheduleId,
    required this.installmentId,
    required this.createdAt,
    this.principalPaid = 0,
    this.interestPaid = 0,
    this.gst = 0,
    this.igst = 0,
    this.processingFee = 0,
    this.insuranceCharge = 0,
    this.serviceCharge = 0,
    this.penalty = 0,
    this.otherCharges = 0,
    this.notes = '',
  });

  @override
  final String id;

  /// The `InstallmentPayment.id` this breakdown belongs to — also this
  /// document's own id.
  final String paymentId;

  /// Denormalized from the owning installment, for query/audit convenience
  /// only — not required for correctness since [paymentId] alone identifies
  /// this record.
  final String scheduleId;
  final String installmentId;

  double principalPaid;
  double interestPaid;
  double gst;
  double igst;
  double processingFee;
  double insuranceCharge;
  double serviceCharge;
  double penalty;
  double otherCharges;
  String notes;

  final DateTime createdAt;

  /// Every charge that isn't principal or interest.
  double get totalCharges => gst + igst + processingFee + insuranceCharge + serviceCharge + penalty + otherCharges;

  double get totalAmountPaid => principalPaid + interestPaid + totalCharges;

  factory EmiPaymentBreakdown.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return EmiPaymentBreakdown(
      id: snapshot.id,
      paymentId: data['paymentId'] as String,
      scheduleId: data['scheduleId'] as String,
      installmentId: data['installmentId'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      principalPaid: (data['principalPaid'] as num?)?.toDouble() ?? 0,
      interestPaid: (data['interestPaid'] as num?)?.toDouble() ?? 0,
      gst: (data['gst'] as num?)?.toDouble() ?? 0,
      igst: (data['igst'] as num?)?.toDouble() ?? 0,
      processingFee: (data['processingFee'] as num?)?.toDouble() ?? 0,
      insuranceCharge: (data['insuranceCharge'] as num?)?.toDouble() ?? 0,
      serviceCharge: (data['serviceCharge'] as num?)?.toDouble() ?? 0,
      penalty: (data['penalty'] as num?)?.toDouble() ?? 0,
      otherCharges: (data['otherCharges'] as num?)?.toDouble() ?? 0,
      notes: data['notes'] as String? ?? '',
    )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'paymentId': paymentId,
      'scheduleId': scheduleId,
      'installmentId': installmentId,
      'createdAt': Timestamp.fromDate(createdAt),
      'principalPaid': principalPaid,
      'interestPaid': interestPaid,
      'gst': gst,
      'igst': igst,
      'processingFee': processingFee,
      'insuranceCharge': insuranceCharge,
      'serviceCharge': serviceCharge,
      'penalty': penalty,
      'otherCharges': otherCharges,
      'notes': notes,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
