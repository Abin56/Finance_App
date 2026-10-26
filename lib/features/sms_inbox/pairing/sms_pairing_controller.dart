import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sms_pairing_providers.dart';
import 'sms_pairing_service.dart';

/// Where the pairing screen is. Pairing itself is two explicit calls — a
/// preview (verify the code for this account) and an approval (the user's
/// tap) — never one.
sealed class SmsPairingState {
  const SmsPairingState();
}

class SmsPairingNoCode extends SmsPairingState {
  const SmsPairingNoCode();
}

class SmsPairingChecking extends SmsPairingState {
  const SmsPairingChecking();
}

class SmsPairingReady extends SmsPairingState {
  const SmsPairingReady(this.preview);
  final SmsPairingPreview preview;
}

class SmsPairingApproving extends SmsPairingState {
  const SmsPairingApproving(this.preview);
  final SmsPairingPreview preview;
}

class SmsPairingFailed extends SmsPairingState {
  const SmsPairingFailed(this.failure, {this.preview});
  final SmsPairingFailure failure;

  /// Set when the failure happened at approval, so a retry can approve again.
  final SmsPairingPreview? preview;
}

class SmsPairingPaired extends SmsPairingState {
  const SmsPairingPaired(this.approval);
  final SmsPairingApproval approval;
}

class SmsPairingCanceled extends SmsPairingState {
  const SmsPairingCanceled();
}

class SmsPairingController extends AutoDisposeNotifier<SmsPairingState> {
  @override
  SmsPairingState build() => const SmsPairingChecking();

  String? get _token => ref.read(pendingSmsPairingProvider).token;

  /// Verifies the pending code for the signed-in account (marks it "opened"
  /// on the web). Does not pair.
  Future<void> start() async {
    final token = _token;
    if (token == null) {
      state = const SmsPairingNoCode();
      return;
    }
    state = const SmsPairingChecking();
    try {
      state = SmsPairingReady(
        await ref.read(smsPairingServiceProvider).preview(token),
      );
    } on SmsPairingException catch (e) {
      state = SmsPairingFailed(e.failure);
    }
  }

  /// The user tapped Approve.
  Future<void> approve({required String uid}) async {
    final token = _token;
    final current = state;
    final preview = switch (current) {
      SmsPairingReady(:final preview) => preview,
      SmsPairingFailed(:final preview?) => preview,
      _ => null,
    };
    if (token == null || preview == null) return;
    state = SmsPairingApproving(preview);
    try {
      final approval = await ref
          .read(smsPairingServiceProvider)
          .approve(token, uid: uid);
      ref.read(pendingSmsPairingProvider).clear();
      ref.invalidate(smsPairedUidProvider);
      state = SmsPairingPaired(approval);
      // First report straight away so the web's "paired" step has company.
      await ref.read(smsDeviceStatusReporterProvider).report(force: true);
    } on SmsPairingException catch (e) {
      state = SmsPairingFailed(
        e.failure,
        preview: e.failure.retryable ? preview : null,
      );
    }
  }

  /// "Not now": the code is canceled server-side so it can't be approved later.
  Future<void> cancel() async {
    final token = _token;
    ref.read(pendingSmsPairingProvider).clear();
    state = const SmsPairingCanceled();
    if (token == null) return;
    try {
      await ref.read(smsPairingServiceProvider).cancel(token);
    } on SmsPairingException {
      // Best effort — the code also expires on its own within minutes.
    }
  }

  Future<void> retry() async {
    final current = state;
    if (current is SmsPairingFailed && current.preview != null) {
      state = SmsPairingReady(current.preview!);
      return;
    }
    await start();
  }

  /// Leaving after a terminal outcome.
  void finish() => ref.read(pendingSmsPairingProvider).clear();
}

final smsPairingControllerProvider =
    AutoDisposeNotifierProvider<SmsPairingController, SmsPairingState>(
      SmsPairingController.new,
    );
