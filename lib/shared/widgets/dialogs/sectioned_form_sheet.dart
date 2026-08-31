import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import '../buttons/primary_button.dart';

/// The flat, sectioned bottom-sheet shell — a colored accent bar across the
/// top, a banded header (title + optional description, close button), a
/// scrollable body for the form's own fields, and a banded footer with
/// Cancel/confirm actions. Mirrors the web app's `SectionedFormDialog`; every
/// new "Add/Edit X" form should build on this instead of hand-rolling its own
/// bare `showModalBottomSheet` body (see [show]).
class SectionedFormSheet extends StatelessWidget {
  const SectionedFormSheet({
    super.key,
    required this.title,
    this.description,
    required this.child,
    required this.onConfirm,
    this.confirmLabel = 'Save',
    this.isSaving = false,
    this.accentColor,
    this.confirmEnabled = true,
    this.showConfirm = true,
  });

  final String title;
  final String? description;
  final Widget child;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final bool isSaving;
  final Color? accentColor;

  /// Disables the confirm button without hiding it — for forms that gate
  /// submission on a live-validated field (e.g. an amount that can't exceed
  /// a remaining balance) rather than solely on [Form] validation.
  final bool confirmEnabled;

  /// Hides the confirm button entirely — for forms whose action changes
  /// meaning per selection (e.g. "settle up" picking a specific expense to
  /// pay, which navigates elsewhere instead of confirming this sheet).
  final bool showConfirm;

  /// Opens this sheet with the theme's default drag handle turned off — the
  /// banded header below carries its own title and close button instead, so
  /// a drag handle on top of that would be a second, redundant "how do I
  /// close this" affordance.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? description,
    required Widget child,
    required VoidCallback onConfirm,
    String confirmLabel = 'Save',
    bool isSaving = false,
    Color? accentColor,
    bool confirmEnabled = true,
    bool showConfirm = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => SectionedFormSheet(
        title: title,
        description: description,
        onConfirm: onConfirm,
        confirmLabel: confirmLabel,
        isSaving: isSaving,
        accentColor: accentColor,
        confirmEnabled: confirmEnabled,
        showConfirm: showConfirm,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = accentColor ?? colors.primary;
    // One continuous surface rather than a distinct gray band — a solid
    // `surfaceContainerHighest` header/footer read as a mismatched stripe
    // sitting above/below the body's own much-lighter tinted fields; a thin
    // hairline still separates the sections without the color jump.
    final bandColor = colors.surface;
    final bandBorder = colors.outlineVariant.withValues(alpha: 0.5);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, color: accent),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.sm, AppSizes.sm),
              decoration: BoxDecoration(color: bandColor, border: Border(bottom: BorderSide(color: bandBorder))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: context.textTheme.titleMedium),
                        if (description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            description!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // A plain square tap target rather than IconButton's default
                  // circular ripple/highlight — mirrors the web app's square
                  // close button on `SectionedFormDialog`, keeping the flat
                  // corner language even on this one control.
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border.all(color: bandBorder)),
                      child: Icon(Icons.close, size: AppSizes.iconSm, color: colors.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSizes.md),
                child: child,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(color: bandColor, border: Border(top: BorderSide(color: bandBorder))),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSaving ? null : () => Navigator.of(context).maybePop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  if (showConfirm)
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: confirmLabel,
                        isLoading: isSaving,
                        onPressed: confirmEnabled ? onConfirm : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
