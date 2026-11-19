import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_sizes.dart';
import '../../extensions/context_extensions.dart';
import '../data/android_update_downloader.dart';
import '../domain/android_release_info.dart';
import '../domain/update_download_state.dart';
import '../providers/android_update_providers.dart';

/// Browser fallback for the known Play Protect risk (see RELEASE.md): the
/// system installer can refuse an internet-sideloaded APK even when this
/// app's own hash check passes, with no on-device way to tell the user why
/// in more specific terms than "blocked".
const String androidPairPageUrl = 'https://flowfi.web.app/pair';

String formatUpdateMegabytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 100 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1);
}

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
      UpdateDownloading(
        :final progress,
        :final receivedBytes,
        :final totalBytes,
        :final resumed,
      ) =>
        _DownloadingView(
          progress: progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          resumed: resumed,
        ),
      UpdateVerifying() => const _BusyView(label: 'Verifying download…'),
      UpdateInstallRequested() => _InstallRequestedView(release: release),
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
    final installedName = ref.watch(installedPackageInfoProvider).value?.version;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          installedName == null
              ? 'Version ${release.version}'
              : 'Version $installedName  →  ${release.version}',
          textAlign: TextAlign.center,
          style: context.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          '${formatUpdateMegabytes(release.sizeBytes)} MB download',
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (release.releaseNotes != null) ...[
          const SizedBox(height: AppSizes.md),
          Text("What's new", style: context.textTheme.labelLarge),
          const SizedBox(height: AppSizes.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Text(
                release.releaseNotes!,
                style: context.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        SizedBox(
          height: AppSizes.buttonHeight,
          child: ElevatedButton(
            onPressed: () =>
                ref.read(androidUpdateDownloadProvider.notifier).start(release),
            child: const Text('Update'),
          ),
        ),
      ],
    );
  }
}

class _DownloadingView extends ConsumerWidget {
  const _DownloadingView({
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    required this.resumed,
  });

  final double? progress;
  final int receivedBytes;
  final int? totalBytes;
  final bool resumed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.colors.onSurface.withValues(alpha: 0.6);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          resumed ? 'Resuming download…' : 'Downloading update…',
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSizes.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: LinearProgressIndicator(value: progress, minHeight: 8),
        ),
        const SizedBox(height: AppSizes.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              progress == null ? '' : '${(progress! * 100).floor()}%',
              style: context.textTheme.bodySmall?.copyWith(color: muted),
            ),
            Text(
              totalBytes == null
                  ? '${formatUpdateMegabytes(receivedBytes)} MB'
                  : '${formatUpdateMegabytes(receivedBytes)} / '
                      '${formatUpdateMegabytes(totalBytes!)} MB',
              style: context.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        TextButton(
          onPressed: () =>
              ref.read(androidUpdateDownloadProvider.notifier).cancel(),
          child: const Text('Cancel'),
        ),
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

class _InstallRequestedView extends ConsumerWidget {
  const _InstallRequestedView({required this.release});

  final AndroidReleaseInfo release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
        const SizedBox(height: AppSizes.md),
        Text(
          'Downloaded and verified. Tap Install in the Android screen that '
          'just opened — FlowFi will restart with your data exactly as it is.',
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSizes.md),
        // The installer was cancelled or dismissed if this app is still
        // running — the verified file is kept, so this never re-downloads.
        TextButton(
          onPressed: () =>
              ref.read(androidUpdateDownloadProvider.notifier).start(release),
          child: const Text('Install again'),
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
          'Download interrupted',
          'Check your connection and try again — the download continues '
              'from where it stopped.',
        ),
      UpdateFailureReason.hashMismatch => (
          'Download looked corrupted',
          'The downloaded file didn\'t match the published update, so it was '
              'discarded. Try again.',
        ),
      UpdateFailureReason.permissionDenied => (
          'Allow installing updates',
          'Android needs your one-time permission for FlowFi to install '
              'updates. Turn on "Allow from this source", come back, and '
              'tap Try again.',
        ),
      UpdateFailureReason.installerBlocked => (
          'Android blocked this install',
          'Your device refused to install the update directly. Open the '
              'download page in your browser instead and install it from '
              'there — your FlowFi data won\'t be affected.',
        ),
      UpdateFailureReason.storage => (
          'Not enough storage',
          'Free up about ${formatUpdateMegabytes(release.sizeBytes)} MB on '
              'your phone, then try again.',
        ),
      UpdateFailureReason.unknown => (
          'Something went wrong',
          message ?? 'Please try again.',
        ),
    };

    void retry() {
      ref.read(androidUpdateDownloadProvider.notifier)
        ..reset()
        ..start(release);
    }

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
        else if (reason == UpdateFailureReason.permissionDenied) ...[
          SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: () =>
                  ref.read(appUpdatePlatformProvider).openInstallSettings(),
              child: const Text('Open settings'),
            ),
          ),
          TextButton(onPressed: retry, child: const Text('Try again')),
        ] else
          SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: retry,
              child: const Text('Try again'),
            ),
          ),
      ],
    );
  }
}
