import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_sizes.dart';
import '../../extensions/context_extensions.dart';
import '../data/android_update_downloader.dart';
import '../domain/android_release_info.dart';
import '../domain/update_download_state.dart';

/// Browser fallback for the known Play Protect risk (see RELEASE.md): the
/// system installer can refuse an internet-sideloaded APK even when this
/// app's own hash check passes, with no on-device way to tell the user why
/// in more specific terms than "blocked".
const String androidPairPageUrl = 'https://flowfi.web.app/pair';

/// Shared download/verify/install UI for both the optional update dialog and
/// the mandatory `/update-required` screen — only the surrounding chrome
/// (dialog vs. full screen) differs between them.
class UpdateProgressView extends ConsumerWidget {
  const UpdateProgressView({super.key, required this.release});

  final AndroidReleaseInfo release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(androidUpdateDownloadProvider);

    return switch (downloadState) {
      UpdateDownloadIdle() => _IdleView(release: release),
      UpdateDownloading(:final progress, :final receivedBytes) =>
        _DownloadingView(progress: progress, receivedBytes: receivedBytes),
      UpdateVerifying() => const _BusyView(label: 'Verifying download…'),
      UpdateInstallRequested() => const _InstallRequestedView(),
      UpdateFailed(:final reason, :final message) =>
        _FailedView(reason: reason, message: message, release: release),
    };
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.release});

  final AndroidReleaseInfo release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Version ${release.version}'
          '${release.sizeBytes > 0 ? ' · ${(release.sizeBytes / (1024 * 1024)).round()} MB' : ''}',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (release.releaseNotes != null) ...[
          const SizedBox(height: AppSizes.sm),
          Text(release.releaseNotes!, style: context.textTheme.bodyMedium),
        ],
        const SizedBox(height: AppSizes.lg),
        SizedBox(
          height: AppSizes.buttonHeight,
          child: ElevatedButton(
            onPressed: () =>
                ref.read(androidUpdateDownloadProvider.notifier).start(release),
            child: const Text('Update Now'),
          ),
        ),
      ],
    );
  }
}

class _DownloadingView extends StatelessWidget {
  const _DownloadingView({required this.progress, required this.receivedBytes});

  final double? progress;
  final int receivedBytes;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Downloading update…', style: context.textTheme.bodyMedium),
        const SizedBox(height: AppSizes.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: LinearProgressIndicator(value: progress),
        ),
        if (progress != null) ...[
          const SizedBox(height: AppSizes.xs),
          Text(
            '${(progress! * 100).round()}%',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: AppSizes.md),
        Text(label, style: context.textTheme.bodyMedium),
      ],
    );
  }
}

class _InstallRequestedView extends StatelessWidget {
  const _InstallRequestedView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
        const SizedBox(height: AppSizes.md),
        Text(
          'Finish the install in the screen Android just opened, then come '
          'back to FlowFi.',
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _FailedView extends ConsumerWidget {
  const _FailedView({
    required this.reason,
    required this.message,
    required this.release,
  });

  final UpdateFailureReason reason;
  final String? message;
  final AndroidReleaseInfo release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, body) = switch (reason) {
      UpdateFailureReason.network => (
          'Download failed',
          'Check your connection and try again.',
        ),
      UpdateFailureReason.hashMismatch => (
          'Download looked corrupted',
          'The downloaded file didn\'t match the published update. Try again.',
        ),
      UpdateFailureReason.permissionDenied => (
          'Permission needed',
          'FlowFi needs permission to install updates. Allow it in Settings, '
              'then try again.',
        ),
      UpdateFailureReason.installerBlocked => (
          'Android blocked this install',
          'Your device refused to install the update directly. Open the '
              'download page in your browser instead and install it from '
              'there — your FlowFi data won\'t be affected.',
        ),
      UpdateFailureReason.unknown => (
          'Something went wrong',
          message ?? 'Please try again.',
        ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline_rounded, color: context.colors.error, size: 40),
        const SizedBox(height: AppSizes.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: context.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          body,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        if (reason == UpdateFailureReason.installerBlocked)
          SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: () => launchUrl(
                Uri.parse(androidPairPageUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Open download page'),
            ),
          )
        else if (reason == UpdateFailureReason.permissionDenied)
          SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings'),
            ),
          )
        else
          SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: () {
                ref.read(androidUpdateDownloadProvider.notifier).reset();
                ref.read(androidUpdateDownloadProvider.notifier).start(release);
              },
              child: const Text('Try again'),
            ),
          ),
      ],
    );
  }
}
