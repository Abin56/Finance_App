import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/clay_theme.dart';

/// One choice in an [showAnchoredSortMenu] dropdown.
class SortMenuOption<T> {
  const SortMenuOption({required this.value, required this.icon, required this.label, this.trailingIcon});

  final T value;
  final IconData icon;
  final String label;

  /// A small secondary icon (e.g. an up/down direction arrow) drawn as a
  /// badge on the corner of [icon]'s chip — null when not needed.
  final IconData? trailingIcon;
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
  final buttonTopLeft = button.localToGlobal(Offset(0, button.size.height + AppSizes.xs), ancestor: overlay);
  final buttonBottomRight = button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay);
  final position = RelativeRect.fromRect(
    Rect.fromPoints(buttonTopLeft, buttonBottomRight),
    Offset.zero & overlay.size,
  );

  return showMenu<T>(
    context: context,
    position: position,
    color: AppClay.card(context),
    surfaceTintColor: Colors.transparent,
    elevation: 10,
    shadowColor: AppClay.primary.withValues(alpha: 0.25),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      side: BorderSide(color: AppClay.primary.withValues(alpha: 0.12)),
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = selected ? colors.primary : colors.onSurface.withValues(alpha: 0.6);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs, horizontal: AppSizes.sm),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(gradient: AppClay.iconChipGradient(tint), shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: tint),
              ),
              if (trailingIcon != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(color: AppClay.card(context), shape: BoxShape.circle),
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
                    color: selected ? colors.primary : null,
                  ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: AppSizes.xs),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border(left: BorderSide(color: selected ? colors.primary : Colors.transparent, width: 3)),
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
