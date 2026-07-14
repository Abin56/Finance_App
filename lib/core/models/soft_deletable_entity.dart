import 'auditable_mixin.dart';
import 'soft_deletable_mixin.dart';

/// Base class every persisted financial entity (Account, Transaction, Bill,
/// Person, ...) should extend. Combines a stable document [id] (so the
/// generic [FirestoreCrudRepository] can address `doc(entity.id)` without
/// per-feature casting) with soft-delete and audit history, so no feature
/// has to reimplement either concern.
abstract class SoftDeletableEntity with SoftDeletableMixin, AuditableMixin {
  String get id;
}
