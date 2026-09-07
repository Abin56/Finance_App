import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../shared/widgets/states/flowfi_icon_chip.dart';

/// One choice in an [showAnchoredSortMenu] dropdown.
class SortMenuOption<T> {
  const SortMenuOption({
    required this.value,
    required this.icon,
    required this.label,
    this.trailingIcon,
    this.color,
  });

  final T value;
  final IconData icon;
  final String label;

  /// A small secondary icon (e.g. an up/down direction arrow) drawn as a
  /// badge on the corner of [icon]'s chip — null when not needed.
  final IconData? trailingIcon;

  /// Overrides the icon chip's own color (e.g. a category's own color) —
  /// null falls back to [SortSheetOptionTile]'s default selected/unselected
  /// tint, right for options with no inherent color of their own (sort
  /// directions, transaction types).
  final Color? color;
}

/// Opens a dropdown of [options] anchored directly beneath [anchorKey]'s
/// widget — expands downward attached to the tapped field itself, like a
/// native `<select>` dropdown, instead of a detached full-screen bottom
/// sheet. Returns the picked value, or null if dismissed without a choice.
Future<T?> showAnchoredSortMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<SortMenuOption<T>> options,
  required T selectedValue,
}) {
  final button = anchorKey.currentContext!.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final buttonTopLeft = button.localToGlobal(
    Offset(0, button.size.height + AppSizes.xs),
    ancestor: overlay,
  );
  final buttonBottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final position = RelativeRect.fromRect(
    Rect.fromPoints(buttonTopLeft, buttonBottomRight),
    Offset.zero & overlay.size,
  );

  final colors = Theme.of(context).colorScheme;
  return showMenu<T>(
    context: context,
    position: position,
    color: colors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 2,
    shadowColor: colors.shadow.withValues(alpha: 0.12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      side: BorderSide(color: colors.outline),
    ),
    constraints: BoxConstraints(
      minWidth: button.size.width.clamp(220, 320),
      maxWidth: 320,
    ),
    items: [
      for (final option in options)
        PopupMenuItem<T>(
          value: option.value,
          height: 44,
          padding: EdgeInsets.zero,
          child: SortSheetOptionTile(
            icon: option.icon,
            trailingIcon: option.trailingIcon,
            label: option.label,
            selected: option.value == selectedValue,
            color: option.color,
            // No onTap: PopupMenuItem itself owns tap handling and pops the
            // menu with `option.value` — see SortSheetOptionTile's doc.
          ),
        ),
    ],
  );
}

/// One row in a [showAnchoredSortMenu] dropdown — an icon, the label, and
/// (when selected) a colored left accent bar plus tinted background and a
/// trailing checkmark, mirroring the "carried forward" left-border
/// convention already used on the People statement screen.
class SortSheetOptionTile extends StatelessWidget {
  const SortSheetOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
    this.trailingIcon,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Null when this tile is placed inside a [PopupMenuItem] (as
  /// [showAnchoredSortMenu] does) — that ancestor already owns tap handling
  /// and closes the menu with its own value, so a nested [InkWell] here
  /// would swallow the tap before it ever reaches the [PopupMenuItem].
  final VoidCallback? onTap;

  /// A small secondary icon (e.g. an up/down direction arrow) drawn as a
  /// badge on the corner of [icon]'s chip — null when not needed.
  final IconData? trailingIcon;

  /// Overrides the icon chip's color — e.g. a category's own color, shown
  /// regardless of selection state. Null keeps the default
  /// selected-primary/unselected-muted tint.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Selected rows are marked by the left accent bar, tinted background,
    // and trailing checkmark below — the label itself stays the ambient
    // text color rather than lime, since lime text on a light popup surface
    // reads poorly (see app_theme.dart's `onSurfaceAccent` note).
    final tint =
        color ??
        (selected ? colors.primary : colors.onSurface.withValues(alpha: 0.6));
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSizes.xs,
        horizontal: AppSizes.sm,
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              FlowFiIconChip(icon: icon, color: tint, size: 28, iconSize: 15),
              if (trailingIcon != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(trailingIcon, size: 11, color: tint),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: AppSizes.xs),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 12,
                color: colors.onPrimary,
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? colors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border(
          left: BorderSide(
            color: selected ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: onTap == null
          ? row
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: row),
            ),
    );
  }
}
