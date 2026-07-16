import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/reminder_notification_service.dart';
import '../../../../core/services/security/app_lock_controller.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../accounts/presentation/widgets/account_form_sheet.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../bills/presentation/widgets/bill_form_sheet.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../credit_cards/presentation/widgets/credit_card_form_sheet.dart';
import '../../../security/presentation/pin_setup_sheet.dart';
import '../../../sms_inbox/domain/sms_availability.dart';
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../providers/setup_wizard_providers.dart';
import '../widgets/setup_step_view.dart';
import '../widgets/setup_wizard_scaffold.dart';

/// The first-time setup wizard, shown once per account right after login and
/// before the dashboard — see the setup gate in `core/router/app_router.dart`.
///
/// It is a pure *orchestrator*: every step drives an existing form sheet or
/// service (accounts, cards, bills, SMS, notifications, app lock) — nothing
/// here creates data or duplicates a form, and every step is a bottom sheet
/// or an in-place permission request, never a navigation away from the
/// wizard. Each step reads its own feature's live state to know when it's
/// satisfied, so adding a bank account (or having done so already) flips that
/// step to "done" on its own.
///
/// Loans are deliberately not a step: the loan form requires a person that
/// already exists (its picker offers no inline creation), so it can't be
/// completed by a brand-new account — it stays available later from the
/// Loans section instead.
///
/// Nothing is mandatory: every step can be skipped, and "Skip for now"
/// dismisses the whole wizard. Whatever is skipped stays configurable later
/// from its normal section — the wizard only ever offers a head start.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  int _index = 0;
  bool _busy = false;

  void _next() {
    // build() clamps _index against the current step count, so a bare
    // increment is safe even if the list shrinks (e.g. SMS drops out on an
    // unsupported platform) — no need to re-read the steps from here, which
    // would mean calling ref.watch outside build.
    setState(() => _index++);
  }

  Future<void> _finish() => ref.read(setupWizardCompletedProvider.notifier).complete();

  /// Runs a step's action with the primary button spinning. Data-driven steps
  /// need no explicit result handling: their feature stream updates and the
  /// wizard rebuilds, flipping the step to done on its own.
  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestNotifications() async {
    await ReminderNotificationService.requestPermission();
    ref.invalidate(notificationsGrantedProvider);
  }

  List<_WizardStep> _buildSteps() {
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final bills = ref.watch(billsStreamProvider).value ?? const [];
    final smsAvailability = ref.watch(smsAvailabilityProvider).value;
    final notificationsGranted = ref.watch(notificationsGrantedProvider).value ?? false;
    final pinEnabled = ref.watch(appLockProvider).pinEnabled;

    final smsSupported = smsAvailability != SmsAvailability.unsupportedPlatform;
    final smsGranted = smsAvailability == SmsAvailability.granted;

    String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'} added';

    return [
      _WizardStep(
        icon: Icons.account_balance_rounded,
        accent: AppColors.primary,
        title: 'Add your bank account',
        description: 'Track balances and transactions from the account you use most. You can add more any time.',
        actionLabel: 'Add bank account',
        doneLabel: accounts.isEmpty ? null : plural(accounts.length, 'account'),
        onAction: () => AccountFormSheet.show(context),
      ),
      _WizardStep(
        icon: Icons.credit_card_rounded,
        accent: AppColors.savings,
        title: 'Add a credit card',
        description: 'Keep an eye on your card balance, statement, and due dates so nothing slips past you.',
        actionLabel: 'Add credit card',
        doneLabel: cards.isEmpty ? null : plural(cards.length, 'card'),
        onAction: () => CreditCardFormSheet.show(context),
      ),
      _WizardStep(
        icon: Icons.receipt_long_rounded,
        accent: AppColors.income,
        title: 'Add a recurring bill',
        description: 'Rent, subscriptions, utilities — add a bill and FlowFi keeps its due date in view.',
        optional: true,
        actionLabel: 'Add a bill',
        doneLabel: bills.isEmpty ? null : plural(bills.length, 'bill'),
        onAction: () => BillFormSheet.show(context),
      ),
      if (smsSupported)
        _WizardStep(
          icon: Icons.mark_email_read_rounded,
          accent: AppColors.info,
          title: 'Scan your bank SMS',
          description: 'Let FlowFi read your bank transaction SMS to suggest expenses. Your messages stay on your device.',
          optional: true,
          actionLabel: 'Enable SMS scan',
          doneLabel: smsGranted ? 'SMS access enabled' : null,
          // Requests the permission in place — reviewing messages happens
          // later in the SMS Inbox. Kept inline (like onboarding) rather than
          // navigating to a screen, so the wizard stays a single flow.
          onAction: () => ref.read(smsAvailabilityProvider.notifier).request(),
        ),
      _WizardStep(
        icon: Icons.notifications_active_rounded,
        accent: AppColors.warning,
        title: 'Turn on reminders',
        description: 'Get a nudge before bills, EMIs, and card dues — and when money owed to you comes due.',
        actionLabel: 'Enable notifications',
        doneLabel: notificationsGranted ? 'Reminders enabled' : null,
        onAction: _requestNotifications,
      ),
      _WizardStep(
        icon: Icons.lock_rounded,
        accent: AppColors.secondary,
        title: 'Protect your data',
        description: 'Lock FlowFi with a PIN, and add fingerprint or face unlock later in Settings.',
        actionLabel: 'Set up a PIN',
        doneLabel: pinEnabled ? 'Protected with a PIN' : null,
        onAction: () => PinSetupSheet.show(context),
      ),
      _WizardStep(
        icon: Icons.celebration_rounded,
        accent: AppColors.primary,
        title: 'You\'re all set!',
        description: 'Your finance workspace is ready. You can always add more accounts, loans, bills, and cards later.',
        actionLabel: 'Go to Dashboard',
        onAction: _finish,
        isCompletion: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    // A dropped step (e.g. SMS on iOS) can leave the index past the end.
    final index = _index.clamp(0, steps.length - 1);
    final step = steps[index];
    final done = step.doneLabel != null;

    final String primaryLabel;
    final VoidCallback onPrimary;
    if (step.isCompletion) {
      primaryLabel = step.actionLabel;
      onPrimary = () => _runAction(step.onAction);
    } else if (done) {
      primaryLabel = 'Continue';
      onPrimary = _next;
    } else {
      primaryLabel = step.actionLabel;
      onPrimary = () => _runAction(step.onAction);
    }

    return SetupWizardScaffold(
      stepIndex: index,
      stepCount: steps.length,
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      primaryBusy: _busy,
      // Nothing to decline on a done step (Continue moves on) or the final
      // one; otherwise a step can always be skipped.
      secondaryLabel: step.isCompletion || done ? null : 'Skip',
      onSecondary: _next,
      onSkipAll: step.isCompletion ? null : _finish,
      footerCaption: step.isCompletion ? 'You can change these anytime in Settings.' : null,
      body: SetupStepView(
        // Re-keyed per step so each entrance animation replays as steps change.
        key: ValueKey(index),
        icon: step.icon,
        accent: step.accent,
        title: step.title,
        description: step.description,
        optional: step.optional,
        doneLabel: step.doneLabel,
      ),
    );
  }
}

/// One wizard step. [doneLabel] is derived from the step's feature state each
/// build — non-null means the step is already satisfied.
class _WizardStep {
  const _WizardStep({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    this.optional = false,
    this.doneLabel,
    this.isCompletion = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final String actionLabel;
  final Future<void> Function() onAction;
  final bool optional;
  final String? doneLabel;
  final bool isCompletion;
}
