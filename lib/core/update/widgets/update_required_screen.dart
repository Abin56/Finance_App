import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_sizes.dart';
import '../../extensions/context_extensions.dart';
import '../domain/android_update_status.dart';
import '../providers/android_update_providers.dart';
import 'update_progress_view.dart';

/// Routed to by `app_router.dart`'s redirect gate whenever
/// `updateRequiredProvider` is true — unlike [UpdateAvailableDialog], this is
/// a normal route (not a dismissible overlay), so there's no back button and
/// no way to reach the rest of the app until the gate itself clears (the
/// installed build updates, or an operator lifts the override).
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(androidUpdateStatusProvider);
    // The gate that routed here already confirmed `UpdateMandatory`; if the
    // override lifts or the installed build catches up while this screen is
    // still mounted, show a brief "all set" state instead of a dead end —
    // the router's own listener (`router_refresh_notifier.dart`) handles
    // actually navigating away.
    final release = switch (status) {
      UpdateMandatory(:final release) => release,
      _ => null,
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    color: context.colors.primary,
                    size: 56,
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: context.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'This version of FlowFi can no longer be used. Install '
                    'the latest update to continue — your data stays exactly '
                    'as it is.',
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: AppSizes.xl),
                  if (release != null) UpdateProgressView(release: release),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
