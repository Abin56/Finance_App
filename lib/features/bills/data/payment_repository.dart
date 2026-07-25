import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/bill.dart';
import '../domain/bill_occurrence.dart';
import '../domain/payment_record.dart';
import 'bill_occurrence_repository.dart';

/// Payment-record persistence for one bill's `users/{uid}/bills/{billId}/payments`
/// subcollection. Constructed per-bill (see `paymentRepositoryProvider`),
/// with a [billOccurrenceRepository] reference so every write keeps the
/// paid-down occurrence's `amountPaid` in sync — the same dependency shape
/// [LedgerRepository] uses for [PersonRepository].
class PaymentRepository extends FirestoreCrudRepository<PaymentRecord> {
  PaymentRepository(super.collection, this.billOccurrenceRepository);

  final BillOccurrenceRepository billOccurrenceRepository;

  /// Records a payment against [occurrence] and applies it toward that
  /// occurrence's progress — mirrors [LedgerRepository.addEntry]'s
  /// sequence.
  Future<PaymentRecord> recordPayment(
    Bill bill,
    BillOccurrence occurrence, {
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('Payment amount must be greater than 0');
    }

    final payment = PaymentRecord(
      id: IdGenerator.generate(),
      billId: bill.id,
      occurrenceId: occurrence.id,
      amount: amount,
      date: date,
      note: note,
      createdAt: DateTime.now(),
    );
    await add(payment.id, payment);
    await billOccurrenceRepository.applyPayment(occurrence, payment.amount);
    return payment;
  }

  /// Reverses the payment's effect on [occurrence], then soft-deletes it —
  /// mirrors [LedgerRepository.softDeleteEntry].
  Future<void> softDeletePayment(BillOccurrence occurrence, PaymentRecord payment) async {
    await billOccurrenceRepository.applyPayment(occurrence, -payment.amount);
    await softDelete(payment);
  }

  /// Re-applies the payment's effect on [occurrence], then restores it —
  /// mirrors [LedgerRepository.restoreEntry].
  Future<void> restorePayment(BillOccurrence occurrence, PaymentRecord payment) async {
    await billOccurrenceRepository.applyPayment(occurrence, payment.amount);
    await restore(payment);
  }

  /// No balance change — already reversed at soft-delete time.
  Future<void> permanentlyDeletePayment(PaymentRecord payment) => permanentlyDelete(payment);

  /// One-time correction setting [payment]'s `occurrenceId`, for a record
  /// written before this field existed. Not a user-facing edit — no audit
  /// entry — since it's a migration backfill, not a change to what the
  /// payment represents (see `BillOccurrenceRepository._adoptLegacy`).
  Future<void> backfillOccurrenceId(PaymentRecord payment, String occurrenceId) async {
    await collection.doc(payment.id).update({'occurrenceId': occurrenceId});
  }
}
