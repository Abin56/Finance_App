import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/shared_credit_limit.dart';

/// Persistence for [SharedCreditLimit] — the bank-issued facility that one
/// or more [CreditCardProfile]s can point at via `sharedLimitId`.
class SharedCreditLimitRepository extends FirestoreCrudRepository<SharedCreditLimit> {
  SharedCreditLimitRepository(super.collection);

  Future<SharedCreditLimit> createSharedLimit({
    required String name,
    required double creditLimit,
  }) async {
    _validate(creditLimit: creditLimit, name: name);
    final sharedLimit = SharedCreditLimit(
      id: IdGenerator.generate(),
      name: name.trim(),
      creditLimit: creditLimit,
      createdAt: DateTime.now(),
    );
    await add(sharedLimit.id, sharedLimit);
    return sharedLimit;
  }

  Future<void> editSharedLimit(
    SharedCreditLimit sharedLimit, {
    String? name,
    double? creditLimit,
  }) async {
    _validate(creditLimit: creditLimit ?? sharedLimit.creditLimit, name: name ?? sharedLimit.name);
    sharedLimit.updateField(
      field: 'name',
      oldValue: sharedLimit.name,
      newValue: name?.trim(),
      apply: (v) => sharedLimit.name = v,
    );
    sharedLimit.updateField(
      field: 'creditLimit',
      oldValue: sharedLimit.creditLimit,
      newValue: creditLimit,
      apply: (v) => sharedLimit.creditLimit = v,
    );
    await update(sharedLimit);
  }

  void _validate({required double creditLimit, required String name}) {
    if (creditLimit <= 0) {
      throw const AppException('Credit limit must be greater than 0');
    }
    if (name.trim().isEmpty) {
      throw const AppException('Name is required');
    }
  }
}
