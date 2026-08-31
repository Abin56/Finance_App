import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// Square gradient color-swatch picker — the flat-design replacement for a
/// row of plain [CircleAvatar] color dots. Each swatch is a genuine two-stop
/// gradient derived from its own base color — deliberately NOT
/// `AppClay.iconChipGradient`, which produces a faint 12–28%-alpha wash meant
/// to sit *behind* an icon glyph; that reads as washed-out and illegible when
/// the color itself is the thing being chosen. Mirrors the web app's account
/// color picker (square swatch, checkmark on the selected one).
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({
    super.key,
    this.colors = AppColors.categoryPalette,
    required this.value,
    required this.onChanged,
  });

  final List<Color> colors;
  final Color value;
  final ValueChanged<Color> onChanged;

  /// A solid, opaque two-stop gradient for [color] — the base color lightened
  /// toward white, so each swatch reads as one clear hue, not a tint.
  static LinearGradient gradientFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lighter = hsl.withLightness((hsl.lightness + 0.16).clamp(0.0, 1.0)).toColor();
    return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, lighter]);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.sm,
      runSpacing: AppSizes.sm,
      children: [
        for (final color in colors)
          _Swatch(
            color: color,
            selected: color.toARGB32() == value.toARGB32(),
            onTap: () => onChanged(color),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Contrast-aware check color — mirrors the web app's `onGradient` fix: a
    // dark swatch needs a white check, a pale one needs a dark check.
    final checkColor = HSLColor.fromColor(color).lightness > 0.6 ? Colors.black87 : Colors.white;

    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: ColorSwatchPicker.gradientFor(color),
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected ? Icon(Icons.check, size: AppSizes.iconSm, color: checkColor) : null,
      ),
    );
  }
}
