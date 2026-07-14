import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/statement.dart';
import '../domain/statement_payment.dart';
import 'statement_repository.dart';

/// Statement-payment persistence for one card's
/// `users/{uid}/creditCards/{cardId}/statements/{statementId}/statementPayments`
/// subcollection — mirrors [PaymentRepository] (Bills) exactly, but also
/// creates the outgoing [Transaction] (expense, from the paying account)
/// that [PaymentRecord] doesn't need to, since a bill payment's source
/// account is implicit while a statement payment explicitly moves money out
/// of a chosen account.
class StatementPaymentRepository extends FirestoreCrudRepository<StatementPayment> {
  StatementPaymentRepository(super.collection, this.statementRepository, this.transactionRepository);

  final StatementRepository statementRepository;
  final TransactionRepository transactionRepository;

  /// Records a payment: creates the outgoing [Transaction] from
  /// [sourceAccountId], then the [StatementPayment] record, then applies it
  /// toward [statement]'s total — mirrors [PaymentRepository.recordPayment]'s
  /// sequence, plus the transaction-creation step Bills doesn't need.
  Future<StatementPayment> recordPayment(
    Statement statement, {
    required double amount,
    required DateTime date,
    required String sourceAccountId,
    required String categoryId,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('Payment amount must be greater than 0');
    }

    final transaction = await transactionRepository.createTransaction(
      type: TransactionType.expense,
      amount: amount,
      dateTime: date,
      accountId: sourceAccountId,
      categoryId: categoryId,
      description: 'Credit card statement payment',
      notes: note,
    );

    final payment = StatementPayment(
      id: IdGenerator.generate(),
      statementId: statement.id,
      amount: amount,
      date: date,
      sourceAccountId: sourceAccountId,
      transactionId: transaction.id,
      note: note,
      createdAt: DateTime.now(),
    );
    await add(payment.id, payment);
    await statementRepository.applyPayment(statement, payment.amount);
    return payment;
  }

  /// Reverses the payment's effect, then soft-deletes it — mirrors
  /// [PaymentRepository.softDeletePayment]. Does not reverse the linked
  /// [Transaction] — trashing a payment record doesn't undo the money
  /// having left the account; that's a separate action on the transaction
  /// itself if the user wants it reversed too.
  Future<void> softDeletePayment(Statement statement, StatementPayment payment) async {
    await statementRepository.applyPayment(statement, -payment.amount);
    await softDelete(payment);
  }

  /// Re-applies the payment's effect, then restores it.
  Future<void> restorePayment(Statement statement, StatementPayment payment) async {
    await statementRepository.applyPayment(statement, payment.amount);
    await restore(payment);
  }

  /// No balance change — already reversed at soft-delete time.
  Future<void> permanentlyDeletePayment(StatementPayment payment) => permanentlyDelete(payment);
}
