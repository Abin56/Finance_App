import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/bill.dart';
import '../domain/payment_record.dart';
import 'bill_repository.dart';

/// Payment-record persistence for one bill's `users/{uid}/bills/{billId}/payments`
/// subcollection. Constructed per-bill (see `paymentRepositoryProvider`),
/// with a [billRepository] reference so every write keeps [Bill.amountPaid]
/// in sync — the same dependency shape [LedgerRepository] uses for
/// [PersonRepository].
class PaymentRepository extends FirestoreCrudRepository<PaymentRecord> {
  PaymentRepository(super.collection, this.billRepository);

  final BillRepository billRepository;

  /// Records a payment and applies it toward the bill's current
  /// occurrence — mirrors [LedgerRepository.addEntry]'s sequence.
  Future<PaymentRecord> recordPayment(
    Bill bill, {
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
      amount: amount,
      date: date,
      note: note,
      createdAt: DateTime.now(),
    );
    await add(payment.id, payment);
    await billRepository.applyPayment(bill, payment.amount);
    return payment;
  }

  /// Reverses the payment's effect, then soft-deletes it — mirrors
  /// [LedgerRepository.softDeleteEntry].
  Future<void> softDeletePayment(Bill bill, PaymentRecord payment) async {
    await billRepository.applyPayment(bill, -payment.amount);
    await softDelete(payment);
  }

  /// Re-applies the payment's effect, then restores it — mirrors
  /// [LedgerRepository.restoreEntry].
  Future<void> restorePayment(Bill bill, PaymentRecord payment) async {
    await billRepository.applyPayment(bill, payment.amount);
    await restore(payment);
  }

  /// No balance change — already reversed at soft-delete time.
  Future<void> permanentlyDeletePayment(PaymentRecord payment) => permanentlyDelete(payment);
}
