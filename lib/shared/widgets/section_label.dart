import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/extensions/context_extensions.dart';

/// Small uppercase micro-heading with a colored accent tick — groups a form
/// sheet's fields into named sections (e.g. "Account Details", "Additional
/// Info"). Mirrors the web app's `SectionLabel`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 3, height: 12, color: context.colors.primary),
        const SizedBox(width: AppSizes.sm),
        Text(
          label.toUpperCase(),
          style: context.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: context.colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
