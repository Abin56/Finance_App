import '../../../core/data/firestore_crud_repository.dart';
import '../domain/emi_payment_breakdown.dart';

/// Persistence for one EMI's `paymentBreakdowns` subcollection — documents
/// are keyed by the `InstallmentPayment.id` they belong to (see
/// `EmiPaymentBreakdown.paymentId`), which trivially enforces the 1:1
/// relationship: creating a second breakdown for the same payment just
/// overwrites, never duplicates. No validation beyond non-negative amounts
/// (mirrors `Statement`'s optional manually-logged fees) — the total isn't
/// cross-checked against the underlying payment's `amount` since the user
/// may record charges paid through a separate transaction.
class EmiPaymentBreakdownRepository extends FirestoreCrudRepository<EmiPaymentBreakdown> {
  EmiPaymentBreakdownRepository(super.collection);

  Future<EmiPaymentBreakdown> createBreakdown({
    required String paymentId,
    required String scheduleId,
    required String installmentId,
    double principalPaid = 0,
    double interestPaid = 0,
    double gst = 0,
    double igst = 0,
    double processingFee = 0,
    double insuranceCharge = 0,
    double serviceCharge = 0,
    double penalty = 0,
    double otherCharges = 0,
    String notes = '',
  }) async {
    final breakdown = EmiPaymentBreakdown(
      id: paymentId,
      paymentId: paymentId,
      scheduleId: scheduleId,
      installmentId: installmentId,
      createdAt: DateTime.now(),
      principalPaid: principalPaid,
      interestPaid: interestPaid,
      gst: gst,
      igst: igst,
      processingFee: processingFee,
      insuranceCharge: insuranceCharge,
      serviceCharge: serviceCharge,
      penalty: penalty,
      otherCharges: otherCharges,
      notes: notes,
    );
    await add(breakdown.id, breakdown);
    return breakdown;
  }
}
