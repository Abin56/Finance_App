import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/update/domain/android_update_status.dart';
import '../../../../core/update/providers/android_update_providers.dart';
import '../../../../core/update/widgets/update_available_dialog.dart';

/// App info — name, tagline, and the installed version (read from the
/// package itself, so it can never drift from `pubspec.yaml`). On the
/// self-updating `sideload` build it also offers a manual "Check for
/// updates"; it is hidden everywhere else (Play flavor, non-Android).
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  bool _checking = false;
  String? _result;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final ok =
        await ref.read(androidReleaseInfoProvider.notifier).refresh(force: true);
    if (!mounted) return;
    final status = ref.read(androidUpdateStatusProvider);
    setState(() {
      _checking = false;
      _result = switch (status) {
        UpdateOptional() || UpdateMandatory() => null,
        UpdateNotAvailable() =>
          ok ? "You're on the latest version." : "Couldn't check for updates.",
      };
    });
    final release = switch (status) {
      UpdateOptional(:final release) => release,
      _ => null,
    };
    if (release != null) {
      await UpdateAvailableDialog.show(context, release: release);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(installedPackageInfoProvider).value;
    final supported = ref.watch(selfUpdateSupportedProvider).value == true;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppStrings.appName, style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppSizes.sm),
                Text(AppStrings.tagline, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSizes.lg),
                Text(
                  info == null
                      ? 'Version'
                      : 'Version ${info.version} (${info.buildNumber})',
                  style: theme.textTheme.bodySmall,
                ),
                if (supported) ...[
                  const SizedBox(height: AppSizes.lg),
                  OutlinedButton(
                    onPressed: _checking ? null : _check,
                    child: Text(_checking ? 'Checking…' : 'Check for updates'),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: AppSizes.sm),
                    Text(_result!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
