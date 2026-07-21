import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// Shared surface shell every dashboard widget card renders inside — same
/// radius/shadow contract as the old `DashboardSectionCard`, just promoted
/// out of the `dashboard` feature so the new widget-based architecture
/// (living under `core/dashboard`) doesn't depend back on it.
class DashboardWidgetCard extends StatelessWidget {
  const DashboardWidgetCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(boxShadow: AppShadows.soft(context)),
          padding: padding ?? const EdgeInsets.all(AppSizes.lg),
          child: child,
        ),
      ),
    );
  }
}

/// The Net-Worth-style hero variant — same radius/shadow, filled with the
/// brand gradient instead of a plain surface color.
class DashboardWidgetGradientCard extends StatelessWidget {
  const DashboardWidgetGradientCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(AppSizes.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: AppShadows.soft(context),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Wraps any widget card with Edit Mode chrome — drag handle, settings,
/// visibility toggle, delete — without the card itself knowing Edit Mode
/// exists. The dashboard shell decides whether to wrap a card in this or
/// render it plain, so every widget builder only ever renders its View Mode
/// content.
class DashboardWidgetEditFrame extends StatelessWidget {
  const DashboardWidgetEditFrame({
    super.key,
    required this.title,
    required this.child,
    required this.isVisible,
    required this.onToggleVisibility,
    required this.onConfigure,
    required this.onDelete,
    this.dragHandle,
  });

  final String title;
  final Widget child;
  final bool isVisible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: isVisible ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
          border: Border.all(color: colors.primary, width: 1.5, style: BorderStyle.solid),
        ),
        padding: const EdgeInsets.all(AppSizes.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
              child: Row(
                children: [
                  ?dragHandle,
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: context.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    iconSize: AppSizes.iconSm,
                    onPressed: onConfigure,
                    tooltip: 'Configure',
                  ),
                  IconButton(
                    icon: Icon(isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    iconSize: AppSizes.iconSm,
                    onPressed: onToggleVisibility,
                    tooltip: isVisible ? 'Hide' : 'Show',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: AppSizes.iconSm,
                    color: colors.error,
                    onPressed: onDelete,
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            IgnorePointer(child: child),
          ],
        ),
      ),
    );
  }
}
