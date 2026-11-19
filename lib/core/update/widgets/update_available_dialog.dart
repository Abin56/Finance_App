import 'package:flutter/material.dart';

import '../../constants/app_sizes.dart';
import '../../extensions/context_extensions.dart';
import '../domain/android_release_info.dart';
import 'update_progress_view.dart';

/// Optional-update prompt, shown once per app session from `AppShell` when
/// `androidUpdateStatusProvider` resolves to `UpdateOptional`. Dismissible —
/// "Later" just closes it; the download/install flow (if started) keeps
/// running even after the dialog is closed, since `androidUpdateDownloadProvider`
/// lives above this dialog in the provider tree.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key, required this.release});

  final AndroidReleaseInfo release;

  static Future<void> show(BuildContext context, {required AndroidReleaseInfo release}) {
    return showDialog<void>(
      context: context,
      builder: (_) => UpdateAvailableDialog(release: release),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.system_update_rounded,
              color: context.colors.primary,
              size: 40,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              'A new version of FlowFi is available',
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSizes.lg),
            UpdateProgressView(release: release),
            const SizedBox(height: AppSizes.md),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          ],
        ),
      ),
    );
  }
}
