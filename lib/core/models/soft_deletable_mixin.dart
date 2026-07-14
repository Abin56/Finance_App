/// Mixed into any entity that should support trash/restore instead of
/// permanent deletion. `permanentlyDelete` (in [HiveCrudRepository]) is the
/// only path that actually removes a record from disk.
mixin SoftDeletableMixin {
  DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  void markDeleted() => deletedAt = DateTime.now();

  void restoreFromTrash() => deletedAt = null;
}
