import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/buttons/primary_button.dart';
import '../constants/app_sizes.dart';
import '../extensions/context_extensions.dart';
import 'app_routes.dart';

/// Shown by [GoRouter]'s `errorBuilder` for any unmatched/invalid route — a
/// malformed or stale deep link, a route to a since-deleted entity, or any
/// other URI go_router can't resolve. Reuses the app's icon-medallion empty
/// state visual language (see `PlaceholderCard`/`SetupStepView`) rather than
/// go_router's bare default error page.
class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final canGoBack = context.canPop();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: context.colors.errorContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.explore_off_rounded, size: AppSizes.iconXl, color: context.colors.error),
              ),
              const SizedBox(height: AppSizes.xl),
              Text(
                'Page Not Found',
                textAlign: TextAlign.center,
                style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                "The page you're looking for doesn't exist or is no longer available.",
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              PrimaryButton(
                label: 'Go to Dashboard',
                onPressed: () => context.go(AppRoutes.dashboard),
              ),
              if (canGoBack) ...[
                const SizedBox(height: AppSizes.sm),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
