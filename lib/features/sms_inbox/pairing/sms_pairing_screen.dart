import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/captured_uid_resolver.dart';
import '../domain/sms_availability.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_ownership_summary.dart';
import '../presentation/providers/sms_auto_sync_providers.dart';
import '../presentation/providers/sms_inbox_providers.dart';
import '../presentation/widgets/sms_historical_recovery_section.dart';
import 'sms_pairing_controller.dart';
import 'sms_pairing_providers.dart';
import 'sms_pairing_service.dart';

/// Opened by the FlowFi Web pairing QR (`flowfi://app/pair?t=…`). Verifies the
/// code for the signed-in account, asks for explicit approval, then walks the
/// user through SMS access and Auto Sync — each step reported to the web so
/// its setup journey follows along. Nothing here imports or creates a
/// transaction; earlier unlinked messages need their own confirmation
/// ("Link earlier messages").
class SmsPairingScreen extends ConsumerStatefulWidget {
  const SmsPairingScreen({super.key});

  @override
  ConsumerState<SmsPairingScreen> createState() => _SmsPairingScreenState();
}

class _SmsPairingScreenState extends ConsumerState<SmsPairingScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(smsPairingControllerProvider.notifier).start(),
    );
  }

  void _leave() {
    ref.read(smsPairingControllerProvider.notifier).finish();
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.smsInbox);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smsPairingControllerProvider);
    final user = ref.watch(authStateProvider).value;
    final controller = ref.read(smsPairingControllerProvider.notifier);

    final Widget body = switch (state) {
      SmsPairingChecking() => const _Busy(label: 'Checking the pairing code…'),
      SmsPairingNoCode() => _Message(
        icon: Icons.qr_code_2_rounded,
        title: 'No pairing code',
        body:
            'Open FlowFi Web on a computer, go to the Transaction Inbox and scan the pairing code shown there.',
        primary: ('Close', _leave),
      ),
      SmsPairingReady(:final preview) ||
      SmsPairingApproving(:final preview) => _Confirm(
        preview: preview,
        email: user?.email,
        approving: state is SmsPairingApproving,
        onApprove: user == null
            ? null
            : () => controller.approve(uid: user.uid),
        onCancel: () async {
          await controller.cancel();
          if (mounted) _leave();
        },
      ),
      SmsPairingFailed(:final failure) => _Message(
        icon: failure == SmsPairingFailure.wrongAccount
            ? Icons.manage_accounts_rounded
            : Icons.error_outline_rounded,
        title: failure == SmsPairingFailure.wrongAccount
            ? 'Different account'
            : "Couldn't pair this phone",
        body: failure == SmsPairingFailure.wrongAccount && user?.email != null
            ? '${failure.message}\n\nSigned in here as ${user!.email}.'
            : failure.message,
        primary: failure == SmsPairingFailure.wrongAccount
            // Signing out keeps the scanned code in memory; signing back in returns here.
            ? (
                'Switch account',
                () => ref.read(authRepositoryProvider).signOut(),
              )
            : failure.retryable
            ? ('Try again', controller.retry)
            : ('Close', _leave),
        secondary:
            failure == SmsPairingFailure.wrongAccount || failure.retryable
            ? ('Cancel', _leave)
            : null,
      ),
      SmsPairingPaired(:final approval) => _PhoneSetup(
        approval: approval,
        onDone: _leave,
      ),
      SmsPairingCanceled() => const _Busy(label: 'Canceled'),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Pair with FlowFi Web')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(state.runtimeType), child: body),
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSizes.lg),
        Text(label, style: context.textTheme.bodyMedium),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.primary,
    this.secondary,
  });
  final IconData icon;
  final String title;
  final String body;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSizes.xl),
    children: [
      Icon(icon, size: 48, color: context.colors.primary),
      const SizedBox(height: AppSizes.lg),
      Text(
        title,
        style: context.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: AppSizes.sm),
      Text(body, style: context.textTheme.bodyMedium?.copyWith(height: 1.45)),
      const SizedBox(height: AppSizes.xl),
      FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
      if (secondary != null)
        TextButton(onPressed: secondary!.$2, child: Text(secondary!.$1)),
    ],
  );
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.preview,
    required this.email,
    required this.approving,
    required this.onApprove,
    required this.onCancel,
  });
  final SmsPairingPreview preview;
  final String? email;
  final bool approving;
  final VoidCallback? onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.onSurface.withValues(alpha: 0.7);
    final active = preview.activeDevice;
    return ListView(
      padding: const EdgeInsets.all(AppSizes.xl),
      children: [
        Icon(
          Icons.phonelink_lock_rounded,
          size: 48,
          color: context.colors.primary,
        ),
        const SizedBox(height: AppSizes.lg),
        Text(
          active?.isThisDevice == true
              ? 'This phone is already paired'
              : 'Pair this phone with FlowFi Web?',
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (email != null) ...[
          const SizedBox(height: AppSizes.sm),
          Text(
            'Account: $email',
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        for (final line in const [
          'Eligible bank SMS alerts found on this phone are sent to your FlowFi account as candidates for review.',
          'Nothing becomes a transaction until you review and import it.',
          'Only alerts that arrive after you signed in are included. Older ones stay on this phone unless you choose to link them.',
          'You can disconnect this phone at any time, here or on the web.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: context.colors.primary,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    line,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (preview.replacesAnotherPhone)
          Container(
            margin: const EdgeInsets.only(top: AppSizes.sm),
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: context.colors.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Text(
              '${active!.label} currently syncs SMS for this account. Approving makes this phone the only one; ${active.label} stops on its next scan.',
              style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        const SizedBox(height: AppSizes.xl),
        FilledButton(
          onPressed: approving ? null : onApprove,
          child: approving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve pairing'),
        ),
        TextButton(
          onPressed: approving ? null : onCancel,
          child: const Text('Not now'),
        ),
      ],
    );
  }
}

/// After approval: SMS access → Auto Sync → first scan. Each action is the
/// user's own tap; each outcome is reported to the web.
class _PhoneSetup extends ConsumerStatefulWidget {
  const _PhoneSetup({required this.approval, required this.onDone});
  final SmsPairingApproval approval;
  final VoidCallback onDone;

  @override
  ConsumerState<_PhoneSetup> createState() => _PhoneSetupState();
}

class _PhoneSetupState extends ConsumerState<_PhoneSetup> {
  SmsAvailability? _permission;
  bool _busy = false;
  bool _scanStarted = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshPermission);
  }

  Future<void> _refreshPermission() async {
    final availability = await ref
        .read(smsPermissionServiceProvider)
        .checkStatus();
    if (!mounted) return;
    setState(() => _permission = availability);
    await ref
        .read(smsDeviceStatusReporterProvider)
        .report(permission: availability, force: true);
  }

  Future<void> _allowSms() async {
    setState(() => _busy = true);
    final availability = await ref
        .read(smsPermissionServiceProvider)
        .requestPermission();
    if (!mounted) return;
    setState(() {
      _permission = availability;
      _busy = false;
    });
    await ref
        .read(smsDeviceStatusReporterProvider)
        .report(permission: availability, force: true);
  }

  Future<void> _enableAutoSync() async {
    setState(() => _busy = true);
    final notifier = ref.read(smsAutoSyncProvider.notifier);
    final enabled = await notifier.enable();
    if (enabled) {
      // The scan reports its own outcome (and uploads, through the F3 gate).
      await notifier.scanNow();
      _scanStarted = true;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(smsAutoSyncProvider).value;
    final muted = context.colors.onSurface.withValues(alpha: 0.7);
    final supported = status?.supported ?? true;
    final permissionOk = _permission == SmsAvailability.granted;
    final autoSyncOn = status?.isEffective ?? false;
    final ownership = summarizeSmsOwnership(
      (ref.watch(smsInboxItemsProvider).value ?? const []).where(
        (i) => i.status == SmsImportStatus.pending,
      ),
      defaultCapturedUidResolver(),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSizes.xl),
      children: [
        Icon(Icons.verified_rounded, size: 48, color: context.colors.primary),
        const SizedBox(height: AppSizes.lg),
        Text(
          'Paired with FlowFi Web',
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          widget.approval.replacedDeviceLabel != null
              ? 'This phone now syncs SMS for your account instead of ${widget.approval.replacedDeviceLabel}. Two quick steps left — FlowFi Web follows along.'
              : 'Two quick steps left. FlowFi Web shows your progress as you go.',
          style: context.textTheme.bodyMedium?.copyWith(
            color: muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSizes.xl),
        if (!supported)
          _StepCard(
            number: 1,
            title: "SMS Sync isn't available in this build",
            body:
                'This version of FlowFi can\'t read SMS. Install the FlowFi Android app from FlowFi Web to use SMS Sync.',
            done: false,
          )
        else ...[
          _StepCard(
            number: 1,
            title: 'Allow SMS access',
            body: switch (_permission) {
              SmsAvailability.granted =>
                'Allowed. FlowFi only reads messages that look like bank alerts.',
              SmsAvailability.permanentlyDenied =>
                'Blocked. Open Settings › Apps › FlowFi › Permissions › SMS and allow it.',
              SmsAvailability.denied =>
                'Declined. FlowFi needs it to find bank alerts — you can allow it now.',
              _ =>
                'FlowFi reads only messages that look like bank transaction alerts.',
            },
            done: permissionOk,
            action:
                permissionOk || _permission == SmsAvailability.permanentlyDenied
                ? null
                : FilledButton(
                    onPressed: _busy ? null : _allowSms,
                    child: const Text('Allow SMS access'),
                  ),
          ),
          _StepCard(
            number: 2,
            title: 'Turn on SMS Auto Sync',
            body: autoSyncOn
                ? (_scanStarted
                      ? 'On. The first scan has started — results appear on FlowFi Web.'
                      : 'On. New bank alerts are picked up in the background.')
                : 'Looks for new bank alerts in the background and sends them to FlowFi Web for review.',
            done: autoSyncOn,
            action: autoSyncOn || !permissionOk
                ? null
                : FilledButton(
                    onPressed: _busy ? null : _enableAutoSync,
                    child: const Text('Turn on Auto Sync'),
                  ),
          ),
          if (autoSyncOn && ownership.missing > 0) ...[
            const SizedBox(height: AppSizes.sm),
            Text(
              '${ownership.missing} earlier message${ownership.missing == 1 ? '' : 's'} on this phone arrived before you signed in, so they aren\'t linked to your account. Link them only if they\'re yours:',
              style: context.textTheme.bodyMedium?.copyWith(
                color: muted,
                height: 1.4,
              ),
            ),
            const SmsHistoricalRecoverySection(),
          ],
        ],
        const SizedBox(height: AppSizes.xl),
        FilledButton.tonal(
          onPressed: widget.onDone,
          child: Text(autoSyncOn ? 'Done' : 'Finish later'),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
    required this.done,
    this.action,
  });
  final int number;
  final String title;
  final String body;
  final bool done;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSizes.md),
    padding: const EdgeInsets.all(AppSizes.lg),
    decoration: BoxDecoration(
      color: context.colors.primary.withValues(alpha: done ? 0.08 : 0.04),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      border: Border.all(
        color: context.colors.primary.withValues(alpha: done ? 0.3 : 0.12),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: done
              ? context.colors.primary
              : context.colors.surfaceContainerHighest,
          child: done
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: context.colors.onPrimary,
                )
              : Text('$number', style: context.textTheme.labelMedium),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                body,
                style: context.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSizes.md),
                action!,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
