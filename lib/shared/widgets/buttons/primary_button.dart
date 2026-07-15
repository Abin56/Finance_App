import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';

/// Primary call-to-action button with a built-in loading state, used for
/// every "Save"/"Add" action so spinners never have to be wired manually.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppSizes.iconSm),
                  const SizedBox(width: AppSizes.sm),
                ],
                // Flexible so a long label ellipsizes instead of overflowing
                // the row at 360dp — the button's width is set by its parent,
                // and the label can't always be guaranteed short.
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
  }
}
