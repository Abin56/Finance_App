import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/android_update_downloader.dart';
import '../domain/android_update_status.dart';
import '../domain/update_download_state.dart';
import '../providers/android_update_providers.dart';
import 'update_available_dialog.dart';

/// Shows the optional-update prompt, and re-evaluates it on every app resume.
///
/// Unlike a bare `ref.listen`, this also evaluates the status that is
/// *already* resolved when it mounts (the check usually finishes while the
/// login/app-lock screen is up, before the main shell exists), so the prompt
/// is never skipped. "Later" snoozes the reminder for one release (24 h);
/// a newer release prompts again immediately. Mandatory updates are not
/// handled here — they are a router gate (`/update-required`).
class UpdatePromptHost extends ConsumerStatefulWidget {
  const UpdatePromptHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends ConsumerState<UpdatePromptHost>
    with WidgetsBindingObserver {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AndroidUpdateStatus>(
      androidUpdateStatusProvider,
      (_, _) => _evaluate(),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _evaluate();
  }

  void _evaluate() {
    // Post-frame: showing a dialog straight from a provider callback can fire
    // mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  Future<void> _maybePrompt() async {
    if (!mounted || _dialogOpen) return;

    // The installed build has caught up (e.g. first launch after an update):
    // the ~140 MB downloaded APK is dead weight.
    final published = ref.read(androidReleaseInfoProvider).value;
    final installed = ref.read(installedVersionCodeProvider).value;
    if (published != null &&
        installed != null &&
        published.versionCode <= installed &&
        !ref.read(androidUpdateDownloadProvider.notifier).isBusy) {
      clearUpdatesCache(ref.read(updatesDirectoryResolverProvider));
    }

    final status = ref.read(androidUpdateStatusProvider);
    if (status is! UpdateOptional) return;

    // Never stack a prompt on top of a download/install already under way.
    final download = ref.read(androidUpdateDownloadProvider);
    if (download is UpdateDownloading ||
        download is UpdateVerifying ||
        download is UpdateInstallRequested) {
      return;
    }

    final store = await ref.read(updateReminderStoreProvider.future);
    if (!mounted || store.isSnoozed(status.release.versionCode)) return;

    _dialogOpen = true;
    try {
      await UpdateAvailableDialog.show(context, release: status.release);
    } finally {
      _dialogOpen = false;
    }

    // Closed without starting an install → remind again in 24 h, not on
    // every resume.
    if (!mounted) return;
    final after = ref.read(androidUpdateDownloadProvider);
    if (after is UpdateDownloadIdle || after is UpdateFailed) {
      await store.snooze(status.release.versionCode);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
