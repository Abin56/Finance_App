import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';

/// One selectable option for a [ChipSelector].
class ChipOption<T> {
  const ChipOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Icon + label selectable chip row — the flat-design replacement for a
/// `DropdownButtonFormField` when the option set is small and fixed (account
/// type, card network, interest type, loan type, ...). Selected = colored
/// border + tinted background. Mirrors the web app's `ChipRow`.
class ChipSelector<T> extends StatelessWidget {
  const ChipSelector({super.key, required this.options, required this.value, required this.onChanged});

  final List<ChipOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.sm,
      runSpacing: AppSizes.sm,
      children: [
        for (final option in options)
          _Chip<T>(option: option, selected: option.value == value, onTap: () => onChanged(option.value)),
      ],
    );
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({required this.option, required this.selected, required this.onTap});

  final ChipOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.primary : colors.onSurface.withValues(alpha: 0.7);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? colors.primary : colors.outline),
          color: selected ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.icon != null) ...[
              Icon(option.icon, size: AppSizes.iconSm, color: fg),
              const SizedBox(width: AppSizes.xs),
            ],
            Text(
              option.label,
              style: context.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
