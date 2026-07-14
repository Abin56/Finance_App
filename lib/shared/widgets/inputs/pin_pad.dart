import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';

/// Row of filled/empty dots showing PIN entry progress. Shared by
/// [LockScreen] and [PinSetupSheet] so the two flows look identical.
class PinDotsIndicator extends StatelessWidget {
  const PinDotsIndicator({
    super.key,
    required this.length,
    required this.filled,
    this.hasError = false,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: AppSizes.xs),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled
                  ? (hasError ? context.colors.error : context.colors.primary)
                  : context.colors.surfaceContainerHighest,
            ),
          ),
      ],
    );
  }
}

/// Numeric keypad (1-9, optional leading action, 0, backspace) used by
/// every PIN entry flow — lock screen unlock and PIN setup/change.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onLeadingAction,
    this.leadingIcon,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onLeadingAction;
  final IconData? leadingIcon;
  final bool enabled;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final digit in row)
                _PadButton(label: digit, onTap: enabled ? () => onDigit(digit) : null),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PadButton(
              icon: leadingIcon,
              onTap: enabled ? onLeadingAction : null,
            ),
            _PadButton(label: '0', onTap: enabled ? () => onDigit('0') : null),
            _PadButton(icon: Icons.backspace_outlined, onTap: enabled ? onBackspace : null),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({this.label, this.icon, this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: label != null
                ? Text(label!, style: Theme.of(context).textTheme.headlineSmall)
                : icon != null
                    ? Icon(icon, size: AppSizes.iconLg)
                    : null,
          ),
        ),
      ),
    );
  }
}
