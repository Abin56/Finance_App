import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Small "go create it there" link — opens the section that owns that record
/// (Accounts, Credit Cards) instead of an inline form. Pushed over the open
/// sheet, so coming back returns to the half-filled form. Mirrors the web
/// app's `AddElsewhereLink`.
class AddElsewhereLink extends StatelessWidget {
  const AddElsewhereLink({super.key, required this.route, required this.label});

  final String route;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.push(route),
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.north_east_rounded, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
