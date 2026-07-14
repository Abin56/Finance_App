import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'category_icons.dart';
import 'category_type.dart';

/// A label (with icon + color) used to classify transactions — "Food",
/// "Salary", etc. Seeded with defaults on first launch; users can also
/// create, edit, deactivate, or soft-delete their own.
class Category extends SoftDeletableEntity {
  Category({
    required this.id,
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorValue,
    required this.createdAt,
    this.isDefault = false,
    this.isActive = true,
  });

  @override
  final String id;
  String name;
  CategoryType type;
  String iconKey;
  int colorValue;
  bool isDefault;
  bool isActive;
  final DateTime createdAt;

  /// Resolves [iconKey] against the fixed [CategoryIcons] catalog — never
  /// stores or constructs raw [IconData] directly, so Flutter's icon
  /// tree-shaking stays intact.
  IconData get icon => CategoryIcons.iconFor(iconKey);

  factory Category.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Category(
      id: snapshot.id,
      name: data['name'] as String,
      type: CategoryTypeX.fromName(data['type'] as String),
      iconKey: data['iconKey'] as String? ?? CategoryIcons.fallback,
      colorValue: data['colorValue'] as int,
      isDefault: data['isDefault'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'type': type.name,
      'iconKey': iconKey,
      'colorValue': colorValue,
      'isDefault': isDefault,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
