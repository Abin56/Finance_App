// Real Firestore commit semantics on top of fake_cloud_firestore, which
// applies a transaction's writes immediately and never rolls back: writes are
// buffered and applied only if the handler completes, and transactions are
// serialized (Firestore guarantees serializable transactions — a conflicting
// concurrent commit is retried against fresh reads, which the lock models).
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:cloud_firestore/cloud_firestore.dart' as fs show Transaction;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

class BufferedTransaction implements fs.Transaction {
  final List<Future<void> Function()> writes = [];
  bool _wrote = false;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) {
    if (_wrote) {
      throw StateError(
        'Firestore transactions require all reads before writes',
      );
    }
    return documentReference.get();
  }

  @override
  fs.Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    _wrote = true;
    writes.add(() => documentReference.set(data));
    return this;
  }

  @override
  fs.Transaction update(
    DocumentReference<Object?> documentReference,
    Map<Object, Object?> data,
  ) {
    _wrote = true;
    writes.add(() => documentReference.update(data));
    return this;
  }

  @override
  fs.Transaction delete(DocumentReference<Object?> documentReference) {
    _wrote = true;
    writes.add(() => documentReference.delete());
    return this;
  }
}

class AtomicFakeFirestore extends FakeFirebaseFirestore {
  Future<void> _tail = Future.value();

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    final result = _tail.then((_) async {
      final tx = BufferedTransaction();
      final value = await transactionHandler(tx);
      for (final write in tx.writes) {
        await write();
      }
      return value;
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
