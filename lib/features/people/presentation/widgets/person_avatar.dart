import 'package:flutter/material.dart';

/// Circular initials avatar colored by [Person.avatarColorValue], reused
/// across list tiles and the statement header.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.colorValue, this.radius = 22});

  final String name;
  final int colorValue;
  final double radius;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        _initials,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: radius * 0.65),
      ),
    );
  }
}
