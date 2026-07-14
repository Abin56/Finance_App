import 'package:flutter/material.dart';

/// A single day's due-date marker on the unified calendar — a pure
/// projection over some feature's own entity (Bill, EMI installment, ...),
/// never persisted. No `BuildContext` dependency, so adapters that produce
/// these stay unit-testable without a widget tree; screens navigate via
/// `context.push(event.routePath)`.
class CalendarEvent {
  const CalendarEvent({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.routePath,
  });

  /// Date-only (no time component) — the key events are grouped by.
  final DateTime date;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final String routePath;
}
