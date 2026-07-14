import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/soft_deletable_entity.dart';

/// Shared CRUD + soft-delete + audit-trail behavior for any Firestore-backed
/// feature repository. Feature repositories (AccountRepository, and later
/// TransactionRepository, BillRepository, PersonRepository...) extend this
/// instead of reimplementing trash/restore/purge logic each time.
class FirestoreCrudRepository<T extends SoftDeletableEntity> {
  FirestoreCrudRepository(this.collection);

  final CollectionReference<T> collection;

  /// Active (non-deleted) records.
  Future<List<T>> getAll() async {
    final snapshot = await collection.where('deletedAt', isNull: true).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// Records currently in trash, awaiting restore or permanent deletion.
  Future<List<T>> getTrash() async {
    final snapshot = await collection.where('deletedAt', isNull: false).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<T?> getByKey(String key) async {
    final snapshot = await collection.doc(key).get();
    return snapshot.data();
  }

  Future<void> add(String id, T entity) => collection.doc(id).set(entity);

  /// Persists in-place edits. Callers should call `entity.recordEdit(...)`
  /// for each changed field *before* calling this, so the audit trail
  /// reflects exactly what changed.
  Future<void> update(T entity) => collection.doc(entity.id).set(entity);

  Future<void> softDelete(T entity) async {
    entity.markDeleted();
    await update(entity);
  }

  Future<void> restore(T entity) async {
    entity.restoreFromTrash();
    await update(entity);
  }

  Future<void> permanentlyDelete(T entity) => collection.doc(entity.id).delete();

  /// Removes trash older than [retention] — backs the "auto-delete after
  /// configurable days" setting. Call periodically (e.g. on app start).
  Future<void> purgeExpiredTrash(Duration retention) async {
    final now = DateTime.now();
    final trashed = await getTrash();
    final expired = trashed.where((e) => now.difference(e.deletedAt!) > retention);
    for (final entity in expired) {
      await permanentlyDelete(entity);
    }
  }

  /// Drives reactive UI via Riverpod `StreamProvider`s without an extra
  /// state-management layer duplicating what Firestore's snapshot stream
  /// already provides.
  Stream<List<T>> watchAll() {
    return collection
        .where('deletedAt', isNull: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Stream<List<T>> watchTrash() {
    return collection
        .where('deletedAt', isNull: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Watches a single document by [id] — for screens/providers that need to
  /// react to one record (e.g. a payment schedule) rather than a whole
  /// collection.
  Stream<T?> watchOne(String id) {
    return collection.doc(id).snapshots().map((snapshot) => snapshot.data());
  }
}
