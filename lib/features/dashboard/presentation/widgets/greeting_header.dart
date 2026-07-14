import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Time-of-day greeting shown at the top of the dashboard, personalized
/// with the signed-in user's first name when available. The bell icon links
/// to Settings for now (notifications land in a later milestone, so there's
/// no notification center yet to link to instead).
class GreetingHeader extends ConsumerWidget {
  const GreetingHeader({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authStateProvider).value?.displayName;
    final firstName = displayName?.trim().split(RegExp(r'\s+')).firstOrNull;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              firstName == null ? _greeting() : '${_greeting()}, $firstName',
              style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              'Here\'s your financial overview',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        IconButton.filledTonal(
          onPressed: () => context.push(AppRoutes.settings),
          icon: const Icon(Icons.notifications_outlined),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ],
    );
  }
}
