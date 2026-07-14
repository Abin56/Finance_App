import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/fiscal_year_controller.dart';
import '../../../../core/services/security/app_lock_controller.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../security/presentation/pin_setup_sheet.dart';

/// Theme, Accounts, and Security (app lock) live here for Milestone 1B.
/// Currency/language/backup/restore land in Milestone 8.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthName(int month) => _monthNames[month - 1];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final lockState = ref.watch(appLockProvider);
    final user = ref.watch(authStateProvider).value;
    final fiscalYearStartMonth = ref.watch(fiscalYearStartMonthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          if (user != null) ...[
            _SettingsSection(
              title: 'Account',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                    child: user.photoUrl == null ? const Icon(Icons.person_outline_rounded) : null,
                  ),
                  title: Text(user.displayName ?? 'Signed in'),
                  subtitle: user.email != null ? Text(user.email!) : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Log out'),
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
          ],
          _SettingsSection(
            title: 'General',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Accounts'),
                subtitle: const Text('Manage cash, bank, and card accounts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.accounts),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.category_outlined),
                title: const Text('Categories'),
                subtitle: const Text('Manage income and expense categories'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.categories),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.donut_large_rounded),
                title: const Text('Budget'),
                subtitle: const Text('Daily, monthly, and category budgets'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.budget),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Savings'),
                subtitle: const Text('Track progress toward your savings goals'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.savings),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline_rounded),
                title: const Text('People'),
                subtitle: const Text('Track money given, borrowed, and repaid'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.people),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Loans'),
                subtitle: const Text('Track money you\'ve lent, with or without interest'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.loans),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('EMIs'),
                subtitle: const Text('Track your monthly EMI payments'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.emis),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SettingsSection(
            title: 'Appearance',
            children: [
              RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (mode) => ref.read(themeModeProvider.notifier).setThemeMode(mode!),
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Light'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Dark'),
                      value: ThemeMode.dark,
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('System default'),
                      value: ThemeMode.system,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SettingsSection(
            title: 'Reports',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Financial Year Starts In'),
                subtitle: const Text('Used by the "Financial Year" report filter'),
                trailing: DropdownButton<int>(
                  value: fiscalYearStartMonth,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var month = 1; month <= 12; month++)
                      DropdownMenuItem(value: month, child: Text(_monthName(month))),
                  ],
                  onChanged: (month) =>
                      ref.read(fiscalYearStartMonthProvider.notifier).setStartMonth(month!),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SettingsSection(
            title: 'Security',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('App Lock'),
                subtitle: const Text('Require a PIN to open the app'),
                value: lockState.pinEnabled,
                onChanged: (enable) async {
                  final controller = ref.read(appLockProvider.notifier);
                  if (enable) {
                    await PinSetupSheet.show(context);
                  } else {
                    await controller.disable();
                  }
                },
              ),
              if (lockState.pinEnabled) ...[
                FutureBuilder<bool>(
                  future: ref.read(appLockProvider.notifier).isBiometricAvailable(),
                  builder: (context, snapshot) {
                    final available = snapshot.data ?? false;
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use biometric unlock'),
                      subtitle: Text(
                        available ? 'Use fingerprint or face unlock' : 'Not available on this device',
                      ),
                      value: lockState.biometricEnabled && available,
                      onChanged: available
                          ? (value) => ref.read(appLockProvider.notifier).setBiometricEnabled(value)
                          : null,
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-lock after'),
                  trailing: DropdownButton<int>(
                    value: lockState.autoLockMinutes,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Immediately')),
                      DropdownMenuItem(value: 1, child: Text('1 minute')),
                      DropdownMenuItem(value: 5, child: Text('5 minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    ],
                    onChanged: (minutes) =>
                        ref.read(appLockProvider.notifier).setAutoLockMinutes(minutes!),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change PIN'),
                  onTap: () => PinSetupSheet.show(context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.sm, left: AppSizes.xs),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.sm),
          child: Column(children: children),
        ),
      ],
    );
  }
}
