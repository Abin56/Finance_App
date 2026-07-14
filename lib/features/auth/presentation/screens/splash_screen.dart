import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';

/// Shown only while the initial auth state is still resolving. Watches
/// nothing — the router's redirect is solely responsible for leaving this
/// screen once [authStateProvider] settles.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_rounded, size: AppSizes.xxxl * 2, color: theme.colorScheme.primary),
            const SizedBox(height: AppSizes.lg),
            Text(AppStrings.appName, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSizes.sm),
            Text(AppStrings.tagline, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSizes.xxl),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
