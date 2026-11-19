import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_sizes.dart';
import '../../extensions/context_extensions.dart';
import '../data/android_update_downloader.dart';
import '../domain/android_release_info.dart';
import '../domain/update_download_state.dart';
import 'update_progress_view.dart';

/// Optional-update prompt, shown by `UpdatePromptHost` when a newer sideload
/// build is published. "Later" snoozes the reminder (see
/// `UpdateReminderStore`); the download/install flow, if started, keeps
/// running even after the dialog is closed, since
/// `androidUpdateDownloadProvider` lives above this dialog.
class UpdateAvailableDialog extends ConsumerWidget {
  const UpdateAvailableDialog({super.key, required this.release});

  final AndroidReleaseInfo release;

  static Future<void> show(BuildContext context, {required AndroidReleaseInfo release}) {
    return showDialog<void>(
      context: context,
      builder: (_) => UpdateAvailableDialog(release: release),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(androidUpdateDownloadProvider);
    final canPostpone = state is UpdateDownloadIdle || state is UpdateFailed;

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
              'Update available',
              textAlign: TextAlign.center,
              style: context.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.md),
            UpdateProgressView(release: release),
            if (canPostpone) ...[
              const SizedBox(height: AppSizes.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
