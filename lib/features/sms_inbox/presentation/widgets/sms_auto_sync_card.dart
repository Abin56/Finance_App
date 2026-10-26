import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../background/sms_background_upload_switch.dart';
import '../../data/captured_uid_resolver.dart';
import '../../domain/notification_access_availability.dart';
import '../../domain/sms_auto_sync_status.dart';
import '../../domain/sms_availability.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_ownership_summary.dart';
import '../../domain/sms_sync_diagnostics.dart';
import '../../domain/sms_sync_health.dart';
import '../../pairing/sms_device_presence.dart';
import '../../pairing/sms_pairing_providers.dart';
import '../../pairing/sms_pairing_status_row.dart';
import '../../pairing/sms_presence_lifecycle.dart';
import '../providers/sms_auto_sync_providers.dart';
import '../providers/sms_inbox_providers.dart';
import 'notification_access_dialog.dart';
import 'sms_consent_sheets.dart';
import 'sms_historical_recovery_section.dart';
import 'sms_sync_visuals.dart';

/// The sync activity both isolates write (foreground scan and the headless
/// worker), re-read every second while the card is on screen.
final smsLiveSyncProvider = StreamProvider.autoDispose<SmsPresenceSync>((
  ref,
) async* {
  while (true) {
    yield await SmsDevicePresenceReporter.readSync();
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// "SMS Sync" for the SMS Inbox: a delivery-tracker style setup (SMS access →
/// notification access → Auto Sync → pair with FlowFi Web), the live sync
/// state, and the support diagnostics folded under Details. Once every
/// required step is done the steps fold into a one-line summary.
///
/// Every step reflects verified state: SMS permission and notification access
/// come from Android, pairing from the server-confirmed local flag. A step
/// only animates to done when that state changes — nothing is simulated.
/// Hidden on builds without the native half (the `play` flavor).
class SmsAutoSyncCard extends ConsumerStatefulWidget {
  const SmsAutoSyncCard({super.key});

  @override
  ConsumerState<SmsAutoSyncCard> createState() => _SmsAutoSyncCardState();
}

class _SmsAutoSyncCardState extends ConsumerState<SmsAutoSyncCard> {
  bool _busy = false;

  /// Only consulted once setup is complete; until then the steps always show.
  bool _expanded = false;

  Future<void> _afterChange() async {
    await ref.read(smsAutoSyncProvider.notifier).refresh();
    ref.invalidate(notificationAccessAvailabilityProvider);
    ref.invalidate(smsPairedUidProvider);
    await ref.read(smsPresenceLifecycleProvider).refresh(force: true);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Disclosure first, then the OS prompt — never silently.
  Future<bool> _allowSms(SmsAutoSyncStatus status) async {
    final current = await ref.read(smsPermissionServiceProvider).checkStatus();
    if (current == SmsAvailability.permanentlyDenied) {
      await ref.read(smsPermissionServiceProvider).openSettings();
      return false;
    }
    if (!mounted || !await SmsAccessConsentSheet.show(context)) return false;
    final result = await ref
        .read(smsPermissionServiceProvider)
        .requestPermission();
    await _afterChange();
    if (result != SmsAvailability.granted) {
      _snack('SMS access is needed for SMS Sync.');
      return false;
    }
    return true;
  }

  Future<void> _setAutoSync(bool on, SmsAutoSyncStatus status) async {
    setState(() => _busy = true);
    final notifier = ref.read(smsAutoSyncProvider.notifier);
    try {
      if (!on) {
        final result = await notifier.disable();
        _snack(switch (result) {
          SmsAutoSyncOffResult.unpaired =>
            'Auto Sync off. FlowFi Web unpaired — pair again to resume.',
          SmsAutoSyncOffResult.unpairPending =>
            "Auto Sync off. Couldn't reach FlowFi to unpair — retrying when you're online.",
          SmsAutoSyncOffResult.notPaired => 'Auto Sync off.',
        });
        return;
      }
      if (!(status.receiveSmsGranted && status.readSmsGranted) &&
          !await _allowSms(status)) {
        return;
      }
      if (await notifier.enable()) {
        // First scan right away (it uploads only once paired).
        await notifier.scanNow();
      }
    } finally {
      await _afterChange();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openNotificationAccess() => NotificationAccessDialog.show(
    context,
    onEnable: () => ref
        .read(notificationAccessAvailabilityProvider.notifier)
        .openSettings(),
  );

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(smsAutoSyncProvider).value;
    if (status == null || !status.supported) return const SizedBox.shrink();

    final notificationAccess = ref
        .watch(notificationAccessAvailabilityProvider)
        .value;
    final uid = defaultCapturedUidResolver();
    final pairedUid = ref.watch(smsPairedUidProvider).value;
    final paired = uid != null && pairedUid == uid;
    final sync =
        ref.watch(smsLiveSyncProvider).value ?? const SmsPresenceSync();
    final smsGranted = status.receiveSmsGranted && status.readSmsGranted;
    final notifGranted =
        notificationAccess == NotificationAccessAvailability.granted;
    final colors = context.colors;
    final textTheme = context.textTheme;
    final muted = smsSyncMuted(context);

    final doneCount = [
      smsGranted,
      status.enabled,
      paired,
    ].where((d) => d).length;
    final allSet = doneCount == 3;
    final showSteps = !allSet || _expanded;

    final steps = <_StepData>[
      _StepData(
        title: 'SMS access',
        subtitle: smsGranted
            ? null
            : status.permissionsRevoked
            ? 'Removed by Android — allow it again'
            : 'Needed to read bank alerts',
        state: smsGranted
            ? SmsSyncStepState.done
            : status.permissionsRevoked
            ? SmsSyncStepState.warn
            : SmsSyncStepState.current,
        action: smsGranted
            ? null
            : _StepAction('Allow', () => _allowSms(status)),
      ),
      _StepData(
        title: 'Notification access',
        subtitle: notifGranted ? null : 'Also catches RCS bank alerts',
        optional: true,
        state: notifGranted ? SmsSyncStepState.done : SmsSyncStepState.optional,
        action: notifGranted
            ? null
            : _StepAction('Turn on', _openNotificationAccess),
      ),
      _StepData(
        title: 'Auto Sync',
        subtitle: status.enabled
            ? (status.isEffective ? null : 'On · waiting for SMS access')
            : 'Picks up new bank alerts in the background',
        state: status.isEffective
            ? SmsSyncStepState.done
            : smsGranted
            ? SmsSyncStepState.current
            : SmsSyncStepState.todo,
        trailing: Switch(
          value: status.enabled,
          onChanged: _busy ? null : (on) => _setAutoSync(on, status),
        ),
      ),
      _StepData(
        title: 'Pair with FlowFi Web',
        subtitle: paired
            ? null
            : status.isEffective
            ? "Scan the QR using your phone's Camera."
            : 'After Auto Sync is on',
        state: paired
            ? SmsSyncStepState.done
            : status.isEffective
            ? SmsSyncStepState.current
            : SmsSyncStepState.todo,
        footer: paired ? const SmsPairingStatusRow() : null,
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: smsSyncBorder(context)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.md,
        AppSizes.lg,
        AppSizes.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: smsSyncAccentWash(context),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Icon(
                  Icons.sync_alt_rounded,
                  size: 18,
                  color: smsSyncAccentInk(context),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SMS Sync',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      allSet
                          ? 'Sending bank alerts to FlowFi Web'
                          : 'Sends bank SMS to FlowFi Web for review',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              _ProgressChip(doneCount: doneCount, allSet: allSet),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          AnimatedSize(
            duration: smsSyncMotion(context, 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: showSteps
                ? Column(
                    key: const ValueKey('steps'),
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        _SetupStep(
                          index: i + 1,
                          data: steps[i],
                          last: i == steps.length - 1,
                        ),
                    ],
                  )
                : _ReadySummary(
                    key: const ValueKey('summary'),
                    notificationsOn: notifGranted,
                  ),
          ),
          _LiveSync(sync: sync, paired: paired, autoSyncOn: status.isEffective),
          if (status.errorLabel != null || status.permissionsRevoked)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: colors.error,
                    ),
                  ),
                  const SizedBox(width: AppSizes.xs),
                  Expanded(
                    child: Text(
                      status.permissionsRevoked
                          ? 'Android removed SMS permission, so Auto Sync is paused.'
                          : status.retryCount > 0
                          ? '${status.errorLabel} (attempt ${status.retryCount})'
                          : status.errorLabel!,
                      style: textTheme.bodySmall?.copyWith(color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSizes.xs),
          Divider(height: 1, color: smsSyncBorder(context)),
          Row(
            children: [
              if (status.isEffective)
                TextButton.icon(
                  onPressed: () =>
                      ref.read(smsAutoSyncProvider.notifier).scanNow(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Scan now'),
                ),
              const Spacer(),
              if (allSet)
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Hide steps' : 'Manage'),
                ),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _SyncDetailsSheet(),
                ),
                child: const Text('Details'),
              ),
            ],
          ),
          // Linking earlier messages uploads them, which needs pairing.
          if (paired) const SmsHistoricalRecoverySection(),
        ],
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.doneCount, required this.allSet});

  final int doneCount;
  final bool allSet;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final colors = context.colors;
    return AnimatedContainer(
      duration: smsSyncMotion(context, 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: allSet ? colors.primary : smsSyncMutedSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: AnimatedSwitcher(
        duration: smsSyncMotion(context, 250),
        child: Row(
          key: ValueKey(allSet ? 'ready' : '$doneCount'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (allSet) ...[
              Icon(Icons.check_rounded, size: 14, color: colors.onPrimary),
              const SizedBox(width: 3),
            ],
            Text(
              allSet ? 'Ready' : '$doneCount of 3',
              style: textTheme.labelMedium?.copyWith(
                color: allSet ? colors.onPrimary : smsSyncMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Folded steps once setup is complete: the three required facts in a row.
class _ReadySummary extends StatelessWidget {
  const _ReadySummary({super.key, required this.notificationsOn});

  final bool notificationsOn;

  @override
  Widget build(BuildContext context) {
    final items = [
      'SMS access',
      if (notificationsOn) 'Notifications',
      'Auto Sync',
      'Paired',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.xs,
          children: [
            for (final label in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: smsSyncAccentInk(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: context.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StepAction {
  const _StepAction(this.label, this.onTap);
  final String label;
  final Future<Object?> Function() onTap;
}

class _StepData {
  const _StepData({
    required this.title,
    required this.subtitle,
    required this.state,
    this.optional = false,
    this.action,
    this.trailing,
    this.footer,
  });

  final String title;

  /// Supporting text — only when it helps (null once a step is simply done).
  final String? subtitle;
  final SmsSyncStepState state;
  final bool optional;
  final _StepAction? action;
  final Widget? trailing;
  final Widget? footer;
}

/// One stop on the tracker: node + connector on the left, copy and the
/// step's control on the right. The connector below a done step fills in.
class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.index,
    required this.data,
    required this.last,
  });

  final int index;
  final _StepData data;
  final bool last;

  /// Node offset inside the 48dp first line, so it centres on the title.
  static const double _nodeTop = 11;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;
    final muted = smsSyncMuted(context);
    final emphasised =
        data.state == SmsSyncStepState.current ||
        data.state == SmsSyncStepState.warn;

    final Widget? control =
        data.trailing ??
        (data.action == null
            ? null
            : emphasised
            ? FilledButton(
                onPressed: data.action!.onTap,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  // The app theme makes buttons full-width; these sit in a row.
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                ),
                child: Text(data.action!.label),
              )
            : OutlinedButton(
                onPressed: data.action!.onTap,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  // The app theme makes buttons full-width; these sit in a row.
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                ),
                child: Text(data.action!.label),
              ));

    return Semantics(
      container: true,
      label: 'Step $index of 4, ${smsSyncStepStateLabel(data.state)}',
      // The connector is a positioned layer spanning the row's full height
      // (whatever the copy wraps to) and reaching into the next step's top
      // padding, so the line stays continuous between nodes.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!last)
            Positioned(
              left: 13,
              width: 2,
              top: _nodeTop + 26 + 3,
              bottom: -(_nodeTop - 3),
              child: SmsSyncConnector(
                filled: data.state == SmsSyncStepState.done,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: _nodeTop, left: 1),
                child: SmsSyncStepNode(state: data.state, index: index),
              ),
              const SizedBox(width: AppSizes.md + 1),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : AppSizes.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          // Narrow (small phone or large text): a button
                          // moves under the copy instead of squeezing it.
                          final stacked =
                              data.trailing == null &&
                              box.maxWidth /
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(1) <
                                  230;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                data.title,
                                                style: textTheme.bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          data.state ==
                                                              SmsSyncStepState
                                                                  .todo
                                                          ? muted
                                                          : null,
                                                    ),
                                              ),
                                              if (data.optional &&
                                                  data.state !=
                                                      SmsSyncStepState.done)
                                                _OptionalTag(),
                                            ],
                                          ),
                                          AnimatedSize(
                                            duration: smsSyncMotion(
                                              context,
                                              200,
                                            ),
                                            alignment: Alignment.topLeft,
                                            child: data.subtitle == null
                                                ? const SizedBox(
                                                    width: double.infinity,
                                                  )
                                                : Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: AnimatedSwitcher(
                                                      duration: smsSyncMotion(
                                                        context,
                                                        200,
                                                      ),
                                                      child: Text(
                                                        data.subtitle!,
                                                        key: ValueKey(
                                                          data.subtitle,
                                                        ),
                                                        style: textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color:
                                                                  data.state ==
                                                                      SmsSyncStepState
                                                                          .warn
                                                                  ? colors.error
                                                                  : muted,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (control != null && !stacked) ...[
                                      const SizedBox(width: AppSizes.sm),
                                      control,
                                    ],
                                  ],
                                ),
                              ),
                              if (control != null && stacked)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSizes.xs,
                                  ),
                                  child: control,
                                ),
                            ],
                          );
                        },
                      ),
                      if (data.footer != null) data.footer!,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionalTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        border: Border.all(color: smsSyncBorder(context)),
      ),
      child: Text(
        'Optional',
        style: context.textTheme.labelSmall?.copyWith(
          color: smsSyncMuted(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The phone's current sync: scanning → uploading n/total → done, with real
/// counts. A determinate bar only when the total is known.
class _LiveSync extends StatelessWidget {
  const _LiveSync({
    required this.sync,
    required this.paired,
    required this.autoSyncOn,
  });

  final SmsPresenceSync sync;
  final bool paired;
  final bool autoSyncOn;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;
    final muted = smsSyncMuted(context);
    final stale =
        sync.updatedAt == null ||
        DateTime.now().difference(sync.updatedAt!) > const Duration(minutes: 5);
    final running = sync.running && !stale;
    final counts =
        '${sync.uploaded} uploaded · ${sync.skipped} skipped${sync.failed > 0 ? ' · ${sync.failed} failed' : ''}';

    final String line;
    if (running) {
      line = sync.phase == SmsPresenceSyncPhase.scanning
          ? 'Reading bank SMS…'
          : sync.total != null && sync.total! > 0
          ? 'Uploading ${sync.done} of ${sync.total} · $counts'
          : 'Uploading…';
    } else if (sync.phase == SmsPresenceSyncPhase.failed) {
      line = "Last sync didn't finish — retries on the next scan";
    } else if (!paired) {
      // A scan before pairing uploads nothing; don't report it as a sync.
      return const SizedBox.shrink();
    } else if (sync.lastSyncAt != null) {
      line =
          'Last sync ${DateFormat('d MMM, h:mm a').format(sync.lastSyncAt!)} · $counts';
    } else if (!paired || !autoSyncOn) {
      return const SizedBox.shrink();
    } else {
      line = 'Waiting for the first sync';
    }

    final fraction = running && sync.total != null && sync.total! > 0
        ? (sync.done / sync.total!).clamp(0.0, 1.0)
        : null;
    final failed = sync.phase == SmsPresenceSyncPhase.failed && !running;

    return AnimatedSize(
      duration: smsSyncMotion(context, 250),
      child: Container(
        margin: const EdgeInsets.only(top: AppSizes.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: smsSyncMutedSurface(context),
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                running
                    ? SmsSyncActivityDot(color: smsSyncAccentInk(context))
                    : Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : Icons.cloud_done_outlined,
                        size: 16,
                        color: failed
                            ? colors.error
                            : smsSyncAccentInk(context),
                      ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    line,
                    style: textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: fraction == null
                    ? const LinearProgressIndicator(minHeight: 3)
                    : TweenAnimationBuilder<double>(
                        tween: Tween(end: fraction),
                        duration: smsSyncMotion(context, 400),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) =>
                            LinearProgressIndicator(value: value, minHeight: 3),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The previous card's support diagnostics, unchanged in substance.
class _SyncDetailsSheet extends ConsumerWidget {
  const _SyncDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(smsAutoSyncProvider).value;
    if (status == null) return const SizedBox.shrink();
    final items = ref.watch(smsInboxItemsProvider).value ?? const [];
    final pendingReview = items
        .where(
          (i) =>
              i.status == SmsImportStatus.pending &&
              !i.isDuplicate &&
              i.parsed != null,
        )
        .length;
    final ownership = summarizeSmsOwnership(
      items,
      defaultCapturedUidResolver(),
    );
    final health = describeSmsSyncHealth(
      ref.watch(smsSyncDiagnosticsProvider).value ?? const SmsSyncDiagnostics(),
      nativeLastSuccessAt: status.lastSuccessAt,
    );
    final textTheme = context.textTheme;
    String fmt(DateTime? t) =>
        t == null ? 'Never' : DateFormat('d MMM, h:mm a').format(t);

    final rows = <(String, String)>[
      ('Last scan attempt', fmt(health.lastAttemptAt)),
      ('Last successful scan', fmt(health.lastScanSuccessAt)),
      ('Waiting to be scanned', '${status.pendingSignals}'),
      ('Awaiting your review', '$pendingReview'),
      ('Cloud Sync', health.cloudLabel),
      if (health.showUploadRow)
        ('Last cloud upload', fmt(health.lastUploadSuccessAt)),
      if (health.showUploadRow) ...[
        ('Pending linked to this account', '${ownership.matching}'),
        ('Pending not linked to any account', '${ownership.missing}'),
        ('Pending linked to another account', '${ownership.mismatching}'),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SMS Sync details',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            "Each transaction's details (amount, merchant, bank, last 4 digits, reference, date) "
            'are saved to your account for review; the message text is not.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSizes.sm),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: textTheme.bodySmall)),
                  Text(
                    value,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          FutureBuilder<String?>(
            future: getOrCreateSmsSyncInstallId(),
            builder: (context, snapshot) => snapshot.data == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sync device ID', style: textTheme.bodySmall),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: SelectableText(
                            snapshot.data!,
                            textAlign: TextAlign.end,
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (health.cloudNote != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              child: Text(health.cloudNote!, style: textTheme.bodySmall),
            ),
          if (health.uploadNote != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              child: Text(
                health.uploadNote!,
                style: textTheme.bodySmall?.copyWith(
                  color: health.uploadNoteIsError ? context.colors.error : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
