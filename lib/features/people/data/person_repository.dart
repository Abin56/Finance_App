import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/person.dart';

/// Person-specific persistence on top of the generic CRUD/soft-delete
/// repository, plus duplicate-person prevention and the balance-sync hook
/// [LedgerRepository] calls on every ledger write.
class PersonRepository extends FirestoreCrudRepository<Person> {
  PersonRepository(super.collection);

  Future<Person> createPerson({
    required String name,
    required int avatarColorValue,
    required double openingBalance,
    String? phone,
    String? email,
    String notes = '',
  }) async {
    final existing = await getAll();
    final normalizedName = name.trim().toLowerCase();
    final isDuplicate = existing.any((p) {
      if (p.name.trim().toLowerCase() != normalizedName) return false;
      if (phone != null && p.phone != null && p.phone == phone) return true;
      if (email != null && p.email != null && p.email == email) return true;
      return false;
    });
    if (isDuplicate) {
      throw const AppException('A person with this name and phone/email already exists');
    }

    final person = Person(
      id: IdGenerator.generate(),
      name: name,
      phone: phone,
      email: email,
      notes: notes,
      avatarColorValue: avatarColorValue,
      openingBalance: openingBalance,
      currentBalance: openingBalance,
      createdAt: DateTime.now(),
    );
    await add(person.id, person);
    return person;
  }

  /// Opening balance is deliberately not editable here — see [Person].
  Future<void> editPerson(
    Person person, {
    String? name,
    String? phone,
    String? email,
    String? notes,
    int? avatarColorValue,
  }) async {
    person.updateField(field: 'name', oldValue: person.name, newValue: name, apply: (v) => person.name = v);
    person.updateField(field: 'phone', oldValue: person.phone, newValue: phone, apply: (v) => person.phone = v);
    person.updateField(field: 'email', oldValue: person.email, newValue: email, apply: (v) => person.email = v);
    person.updateField(field: 'notes', oldValue: person.notes, newValue: notes, apply: (v) => person.notes = v);
    person.updateField(
      field: 'avatarColor',
      oldValue: person.avatarColorValue,
      newValue: avatarColorValue,
      apply: (v) => person.avatarColorValue = v,
    );
    await update(person);
  }

  /// Applies a signed delta to a person's running balance — the hook
  /// [LedgerRepository] calls on every ledger write so `currentBalance`
  /// never has to be derived by summing every ledger entry on each read.
  /// Mirrors [AccountRepository.adjustBalance] exactly.
  Future<void> adjustBalance(Person person, double delta) async {
    if (delta == 0) return;
    final newBalance = person.currentBalance + delta;
    person.recordEdit(
      field: 'currentBalance',
      oldValue: person.currentBalance.toString(),
      newValue: newBalance.toString(),
    );
    person.currentBalance = newBalance;
    await update(person);
  }
}
