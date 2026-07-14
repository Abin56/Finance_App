import 'package:flutter/material.dart';

import '../../../../shared/widgets/states/empty_state.dart';

/// Placeholder destination for menu entries whose feature doesn't exist
/// yet (e.g. Backup & Restore) — a stub, not a fabricated feature, so the
/// "More" menu's structure is honest about what's actually built.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, this.title = 'Coming Soon'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const EmptyState(
        icon: Icons.hourglass_empty_rounded,
        title: 'Coming soon',
        subtitle: 'This feature is not available yet.',
      ),
    );
  }
}
