import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/sms_inbox/presentation/widgets/notification_access_dialog.dart';

/// Throwaway entrypoint used only to visually inspect
/// [NotificationAccessDialog] on a real device without wiring through SMS/
/// notification-access permission state. Not part of the app — delete after
/// review.
void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationAccessDialog.show(context, onEnable: () {});
            });
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }
}
