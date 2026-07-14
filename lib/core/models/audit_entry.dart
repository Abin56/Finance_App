import 'package:cloud_firestore/cloud_firestore.dart';

/// A single recorded change to a financial entity — what field changed,
/// its old and new value, and when. Entities never overwrite history;
/// every edit appends one of these instead.
class AuditEntry {
  AuditEntry({
    required this.timestamp,
    required this.field,
    required this.oldValue,
    required this.newValue,
  });

  final DateTime timestamp;
  final String field;
  final String oldValue;
  final String newValue;

  Map<String, dynamic> toMap() => {
    'timestamp': Timestamp.fromDate(timestamp),
    'field': field,
    'oldValue': oldValue,
    'newValue': newValue,
  };

  factory AuditEntry.fromMap(Map<String, dynamic> map) {
    return AuditEntry(
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      field: map['field'] as String,
      oldValue: map['oldValue'] as String,
      newValue: map['newValue'] as String,
    );
  }
}
