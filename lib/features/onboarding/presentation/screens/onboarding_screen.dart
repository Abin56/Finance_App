import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/reminder_notification_service.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../security/presentation/pin_setup_sheet.dart';
import '../../../sms_inbox/domain/sms_availability.dart';
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../providers/onboarding_providers.dart';
import '../widgets/onboarding_illustration.dart';
import '../widgets/onboarding_page_view.dart';
import '../widgets/onboarding_progress_dots.dart';

/// The first-launch intro tour, shown before sign-in so people understand
/// what FlowFi does before being asked to hand over an account — see the
/// onboarding gate in `core/router/app_router.dart`.
///
/// Six pages, three of which do real work rather than just talk: SMS
/// detection, notifications, and app lock each request their permission here
/// so the user grants it in context, right under the copy explaining why.
/// Every one of them is optional — the matching feature asks again later if
/// skipped, so nothing breaks by declining.
///
/// Two different escapes, deliberately distinct: "Skip" in the top bar
/// leaves the tour entirely, while a page's secondary button declines only
/// that page's step and moves on.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  /// The tour's three buttons are keyed because their labels alone are
  /// ambiguous: "Skip" is both the top bar's leave-the-tour action and, on
  /// other pages, the secondary decline-this-step action.
  static const skipTourKey = ValueKey('onboarding_skip_tour');
  static const primaryActionKey = ValueKey('onboarding_primary_action');
  static const secondaryActionKey = ValueKey('onboarding_secondary_action');

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// Marks the tour seen and lets the router take over — completing flips
  /// the onboarding gate, which hands off to the auth gate (i.e. login).
  Future<void> _finish() => ref.read(onboardingCompletedProvider.notifier).complete();

  /// Runs a page's permission request with the primary button spinning, then
  /// advances regardless of the answer: every step is optional, so "no" is a
  /// valid outcome that still moves the tour forward.
  Future<void> _runThenAdvance(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) _next();
  }

  Future<void> _enableSms() => _runThenAdvance(
        () => ref.read(smsAvailabilityProvider.notifier).request(),
      );

  Future<void> _enableNotifications() => _runThenAdvance(
        () => ReminderNotificationService.requestPermission(),
      );

  Future<void> _secureApp() => _runThenAdvance(() => PinSetupSheet.show(context));

  /// The SMS page adapts to what the device can actually do: there is no
  /// public SMS-reading API on iOS, and a re-run of onboarding on a device
  /// that already granted access shouldn't offer to ask again.
  bool get _canRequestSms {
    final availability = ref.watch(smsAvailabilityProvider).value;
    return availability != SmsAvailability.granted &&
        availability != SmsAvailability.unsupportedPlatform;
  }

  List<_OnboardingStep> _steps() {
    return [
      _OnboardingStep(
        page: const OnboardingPageView(
          icon: Icons.account_balance_wallet_rounded,
          gradient: AppColors.primaryGradient,
          headline: 'Manage all your money in one place.',
          subtitle: 'Track expenses, income, credit cards, loans, bills, and cash flow — all together.',
          badges: [
            OnboardingBadge(
              icon: Icons.trending_up_rounded,
              color: AppColors.income,
              alignment: Alignment(-0.95, -0.55),
            ),
            OnboardingBadge(
              icon: Icons.credit_card_rounded,
              color: AppColors.savings,
              alignment: Alignment(0.95, 0.45),
            ),
          ],
        ),
        primaryLabel: 'Get Started',
        onPrimary: _next,
      ),
      _OnboardingStep(
        page: const OnboardingPageView(
          icon: Icons.mark_email_unread_rounded,
          gradient: AppColors.savingsGradient,
          headline: 'Smart SMS detection',
          subtitle:
              'FlowFi can recognize your bank transaction SMS to help you record expenses faster.',
          note: 'Your SMS stays on your device until you choose to convert it.',
          badges: [
            OnboardingBadge(
              icon: Icons.sms_rounded,
              color: AppColors.primary,
              alignment: Alignment(-0.95, 0.5),
            ),
            OnboardingBadge(
              icon: Icons.bolt_rounded,
              color: AppColors.pending,
              alignment: Alignment(0.95, -0.5),
            ),
          ],
        ),
        primaryLabel: _canRequestSms ? 'Enable SMS Detection' : 'Continue',
        onPrimary: _canRequestSms ? _enableSms : _next,
        secondaryLabel: _canRequestSms ? 'Skip for Now' : null,
      ),
      _OnboardingStep(
        page: const OnboardingPageView(
          icon: Icons.receipt_long_rounded,
          gradient: AppColors.incomeGradient,
          headline: 'Every payment, tracked',
          subtitle:
              'Bills, EMIs, and credit card dues all share one payment engine — so what\'s paid, what\'s pending, and what\'s next is never a guess.',
          badges: [
            OnboardingBadge(
              icon: Icons.check_circle_rounded,
              color: AppColors.income,
              alignment: Alignment(0.95, -0.5),
            ),
            OnboardingBadge(
              icon: Icons.schedule_rounded,
              color: AppColors.pending,
              alignment: Alignment(-0.95, 0.5),
            ),
          ],
        ),
        primaryLabel: 'Continue',
        onPrimary: _next,
      ),
      _OnboardingStep(
        page: const OnboardingPageView(
          icon: Icons.notifications_active_rounded,
          gradient: [AppColors.pending, AppColors.expense],
          headline: 'Never miss an important payment.',
          subtitle:
              'Get reminders for bills, EMIs, credit card due dates, and money owed to you — right when they matter.',
          badges: [
            OnboardingBadge(
              icon: Icons.event_rounded,
              color: AppColors.primary,
              alignment: Alignment(-0.95, -0.5),
            ),
            OnboardingBadge(
              icon: Icons.savings_rounded,
              color: AppColors.income,
              alignment: Alignment(0.95, 0.5),
            ),
          ],
        ),
        primaryLabel: 'Enable Notifications',
        onPrimary: _enableNotifications,
        secondaryLabel: 'Skip',
      ),
      _OnboardingStep(
        page: const OnboardingPageView(
          icon: Icons.shield_rounded,
          gradient: [AppColors.primary, AppColors.secondary],
          headline: 'Protect your financial data.',
          subtitle:
              'Lock FlowFi with a PIN, and add fingerprint or face unlock where your device supports it. Your PIN is encrypted and never leaves this device.',
          badges: [
            OnboardingBadge(
              icon: Icons.fingerprint_rounded,
              color: AppColors.secondary,
              alignment: Alignment(0.95, -0.5),
            ),
            OnboardingBadge(
              icon: Icons.lock_rounded,
              color: AppColors.primary,
              alignment: Alignment(-0.95, 0.5),
            ),
          ],
        ),
        primaryLabel: 'Secure My App',
        onPrimary: _secureApp,
        secondaryLabel: 'Skip',
      ),
      _OnboardingStep(
        page: const OnboardingPageView(
          icon: Icons.celebration_rounded,
          gradient: AppColors.primaryGradient,
          headline: 'You\'re all set!',
          subtitle: 'Let\'s start managing your money smarter.',
          badges: [
            OnboardingBadge(
              icon: Icons.check_rounded,
              color: AppColors.income,
              alignment: Alignment(-0.95, -0.5),
            ),
            OnboardingBadge(
              icon: Icons.auto_awesome_rounded,
              color: AppColors.pending,
              alignment: Alignment(0.95, 0.5),
            ),
          ],
        ),
        primaryLabel: 'Start Using FlowFi',
        onPrimary: _finish,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    final step = steps[_index];
    final isLast = _index == steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.md, 0),
              child: Row(
                children: [
                  OnboardingProgressDots(count: steps.length, currentIndex: _index),
                  const Spacer(),
                  // Nothing left to skip on the final page, and its single
                  // action already ends the tour.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: isLast ? 0 : 1,
                    child: TextButton(
                      key: OnboardingScreen.skipTourKey,
                      onPressed: isLast ? null : _finish,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _index = index),
                itemCount: steps.length,
                itemBuilder: (context, index) => steps[index].page,
              ),
            ),
            _ActionBar(
              primaryLabel: step.primaryLabel,
              onPrimary: step.onPrimary,
              secondaryLabel: step.secondaryLabel,
              onSecondary: _next,
              isBusy: _busy,
            ),
          ],
        ),
      ),
    );
  }
}

/// One page of the tour plus the buttons the host renders for it.
class _OnboardingStep {
  const _OnboardingStep({
    required this.page,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
  });

  final Widget page;
  final String primaryLabel;
  final VoidCallback onPrimary;

  /// Declines this page's step and moves on. Null on pages with nothing to
  /// decline, where the top bar's "Skip" is the only way out.
  final String? secondaryLabel;
}

/// The fixed bottom actions. Its height never changes between pages — the
/// secondary slot keeps its space even when empty — so the primary button
/// stays put instead of hopping as you swipe.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.isBusy,
  });

  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback onSecondary;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.lg, AppSizes.xl, AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: AppSizes.buttonHeight,
            child: PrimaryButton(
              key: OnboardingScreen.primaryActionKey,
              label: primaryLabel,
              onPressed: isBusy ? null : onPrimary,
              isLoading: isBusy,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          SizedBox(
            height: AppSizes.buttonHeight - AppSizes.sm,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              // Keyed on the label so a changed label cross-fades; the
              // button underneath keeps a stable key for callers and tests.
              child: secondaryLabel == null
                  ? const SizedBox.shrink()
                  : KeyedSubtree(
                      key: ValueKey(secondaryLabel),
                      child: TextButton(
                        key: OnboardingScreen.secondaryActionKey,
                        onPressed: isBusy ? null : onSecondary,
                        child: Text(
                          secondaryLabel!,
                          style: context.textTheme.labelLarge?.copyWith(
                            color: context.colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
