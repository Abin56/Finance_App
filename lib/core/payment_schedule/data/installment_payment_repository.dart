import '../../data/firestore_crud_repository.dart';
import '../../errors/app_exception.dart';
import '../../utils/id_generator.dart';
import '../domain/installment.dart';
import '../domain/installment_payment.dart';
import 'installment_repository.dart';

/// Payment-record persistence for one installment's
/// `.../installments/{installmentId}/payments` subcollection. Constructed
/// per-installment, with an [installmentRepository] reference so every
/// write keeps [Installment.amountPaid] in sync — mirrors `PaymentRepository`
/// exactly.
class InstallmentPaymentRepository extends FirestoreCrudRepository<InstallmentPayment> {
  InstallmentPaymentRepository(super.collection, this.installmentRepository);

  final InstallmentRepository installmentRepository;

  /// Records a payment and applies it toward the installment. Supports
  /// partial payments (amount < remaining) and early/advance payments
  /// (date before the installment's due date) with no special-case code —
  /// any positive amount/date is accepted.
  Future<InstallmentPayment> recordPayment(
    Installment installment, {
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('Payment amount must be greater than 0');
    }

    final payment = InstallmentPayment(
      id: IdGenerator.generate(),
      installmentId: installment.id,
      scheduleId: installment.scheduleId,
      ownerType: installment.ownerType,
      ownerId: installment.ownerId,
      amount: amount,
      date: date,
      note: note,
      createdAt: DateTime.now(),
    );
    await add(payment.id, payment);
    await installmentRepository.applyPayment(installment, payment.amount);
    return payment;
  }

  /// Reverses the payment's effect, then soft-deletes it.
  Future<void> softDeletePayment(Installment installment, InstallmentPayment payment) async {
    await installmentRepository.applyPayment(installment, -payment.amount);
    await softDelete(payment);
  }

  /// Re-applies the payment's effect, then restores it.
  Future<void> restorePayment(Installment installment, InstallmentPayment payment) async {
    await installmentRepository.applyPayment(installment, payment.amount);
    await restore(payment);
  }

  /// No balance change — already reversed at soft-delete time.
  Future<void> permanentlyDeletePayment(InstallmentPayment payment) => permanentlyDelete(payment);
}
