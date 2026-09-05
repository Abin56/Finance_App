import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';

/// A consistent, premium-feeling empty state used across every list screen
/// (transactions, bills, reports, search) instead of bare "no data" text.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Centers normally, but scrolls instead of overflowing on the rare
    // occasion the available height is squeezed too tight to fit (e.g. the
    // keyboard is still up when a search yields an empty result) — a
    // LayoutBuilder + minHeight ConstrainedBox rather than a bare Center so
    // a few px of overflow becomes a scroll, not a render error.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: context.colors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: AppSizes.iconXl, color: context.colors.primary),
                    ),
                    const SizedBox(height: AppSizes.xl),
                    Text(
                      title,
                      style: context.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(
                      subtitle,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (action != null) ...[
                      const SizedBox(height: AppSizes.xl),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
