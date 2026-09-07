import 'package:flutter/material.dart';

/// A thin convenience wrapper over [AlertDialog] for new dialogs — the
/// visual styling itself (radius, background, elevation, title/content text
/// style) now comes entirely from `app_theme.dart`'s `dialogTheme`, which
/// didn't exist before Theme V2 (dialogs used to fall back to Material 3's
/// stock look). This wrapper's only job is giving call sites a consistent
/// way to build the action row via [AppDialogActions] rather than
/// hand-rolling button styles that might fight the theme.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
  });

  final String title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(title: Text(title), content: content, actions: actions);
  }
}

/// Consistent dialog action roles: neutral cancel, lime/primary confirm
/// (inherits the elevated-button theme's lime-fill/near-black-text), and a
/// red destructive action — never lime, per the color-usage rule.
abstract class AppDialogActions {
  AppDialogActions._();

  static Widget cancel(
    BuildContext context, {
    String label = 'Cancel',
    VoidCallback? onPressed,
  }) {
    return TextButton(
      onPressed: onPressed ?? () => Navigator.of(context).pop(false),
      child: Text(label),
    );
  }

  static Widget confirm(
    BuildContext context, {
    String label = 'Confirm',
    VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed ?? () => Navigator.of(context).pop(true),
      child: Text(label),
    );
  }

  static Widget destructive(
    BuildContext context, {
    String label = 'Delete',
    VoidCallback? onPressed,
  }) {
    final error = Theme.of(context).colorScheme.error;
    return TextButton(
      onPressed: onPressed ?? () => Navigator.of(context).pop(true),
      style: TextButton.styleFrom(foregroundColor: error),
      child: Text(label),
    );
  }
}
