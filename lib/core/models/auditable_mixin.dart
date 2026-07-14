import 'audit_entry.dart';

/// Mixed into any entity that must preserve a full edit history instead of
/// silently overwriting financial values (accounting-safe editing).
mixin AuditableMixin {
  DateTime? lastEditedAt;
  List<AuditEntry> editHistory = [];

  /// Appends an audit entry; never mutates or removes prior entries.
  void recordEdit({required String field, required String oldValue, required String newValue}) {
    if (oldValue == newValue) return;
    final now = DateTime.now();
    editHistory = [
      ...editHistory,
      AuditEntry(timestamp: now, field: field, oldValue: oldValue, newValue: newValue),
    ];
    lastEditedAt = now;
  }

  /// Collapses the standard "diff, assign, record" sequence every edit
  /// method otherwise repeats per field. Pass the field's current value,
  /// the incoming value (or null if unchanged), and how to apply it:
  ///
  /// ```dart
  /// editable.updateField(field: 'name', oldValue: name, newValue: newName, apply: (v) => name = v);
  /// ```
  ///
  /// No-ops when [newValue] is null or equal to [oldValue], so callers can
  /// pass straight through optional edit parameters without their own checks.
  void updateField<V>({
    required String field,
    required V oldValue,
    required V? newValue,
    required void Function(V value) apply,
  }) {
    if (newValue == null || newValue == oldValue) return;
    apply(newValue);
    recordEdit(field: field, oldValue: oldValue.toString(), newValue: newValue.toString());
  }
}
