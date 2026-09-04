import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// The "More" tab — secondary destinations that don't need their own
/// bottom-nav slot: Reports (analysis, kept deliberately separate from the
/// Cash Flow tab's planning focus), Settings, Credit Cards, Savings Goals,
/// Categories, Backup & Restore, Trash, and About.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  // Colors mirror the web app's semantic icon-accent map (icon-reports,
  // icon-credit-card, icon-savings, ...) so each destination reads with the
  // same tint on both platforms instead of one flat "everything is primary
  // blue" list.
  // One accent per section instead of one per row — a scattered rainbow of
  // 8 unrelated colors read as noisy. Trash keeps red on its own: that's a
  // meaningful destructive-action signal, not decoration, so it stays
  // distinct even within the neutral "App" section.
  static const _financeItems = [
    _MoreItem(
      icon: Icons.pie_chart_outline_rounded,
      label: 'Reports',
      subtitle: 'Spending trends and analysis',
      route: AppRoutes.reports,
      color: AppColors.primary,
    ),
    _MoreItem(
      icon: Icons.credit_card_outlined,
      label: 'Credit Cards',
      subtitle: 'Manage cards and statements',
      route: AppRoutes.creditCards,
      color: AppColors.primary,
    ),
    _MoreItem(
      icon: Icons.savings_outlined,
      label: 'Savings Goals',
      subtitle: 'Track progress toward targets',
      route: AppRoutes.savings,
      color: AppColors.primary,
    ),
    _MoreItem(
      icon: Icons.category_outlined,
      label: 'Categories',
      subtitle: 'Organize income and expenses',
      route: AppRoutes.categories,
      color: AppColors.primary,
    ),
  ];

  static const _appItemNeutral = Color(0xFF64748B);

  static const _appItems = [
    _MoreItem(
      icon: Icons.settings_outlined,
      label: 'Settings',
      subtitle: 'Account, preferences, sign out',
      route: AppRoutes.settings,
      color: _appItemNeutral,
    ),
    _MoreItem(
      icon: Icons.cloud_upload_outlined,
      label: 'Backup & Restore',
      subtitle: 'Keep your data safe',
      route: AppRoutes.comingSoon,
      color: _appItemNeutral,
    ),
    _MoreItem(
      icon: Icons.delete_outline_rounded,
      label: 'Trash',
      subtitle: 'Recently deleted items',
      route: AppRoutes.trash,
      color: AppColors.error,
    ),
    _MoreItem(
      icon: Icons.info_outline_rounded,
      label: 'About',
      subtitle: 'App version and information',
      route: AppRoutes.about,
      color: _appItemNeutral,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppClay.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.apps_rounded, size: AppSizes.iconSm, color: Colors.white),
            ),
            const SizedBox(width: AppSizes.sm),
            Text(
              'More',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          // Bottom padding clears the shell's floating "+" button, same
          // convention as every other bottom-nav tab.
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.fabClearance),
          children: [
            _ProfileCard(
              name: user?.displayName,
              email: user?.email,
              onTap: () => context.push(AppRoutes.settings),
            ),
            const SizedBox(height: AppSizes.lg),
            const SectionLabel('Finance Tools'),
            const SizedBox(height: AppSizes.sm),
            _MoreGroup(items: _financeItems),
            const SizedBox(height: AppSizes.lg),
            const SectionLabel('App'),
            const SizedBox(height: AppSizes.sm),
            _MoreGroup(items: _appItems),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the web sidebar's user-profile row — an initials avatar, name/
/// email, and a chevron through to Settings (where the actual account
/// actions, including sign-out, already live) — the More tab's one personal
/// touch instead of opening straight into a flat menu.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.name, required this.email, required this.onTap});

  final String? name;
  final String? email;
  final VoidCallback onTap;

  String get _initials {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return (email?.isNotEmpty ?? false) ? email![0].toUpperCase() : '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      isHero: true,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: AppClay.primaryGradient,
      ),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Text(
              _initials,
              style: context.textTheme.bodyLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (name?.isNotEmpty ?? false) ? name! : 'Your account',
                  style: context.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    style: context.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.route,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String route;
  final Color color;
}

/// One labeled group of menu rows — each item is its own floating card
/// with a gap between, rather than one shared card with thin dividers.
class _MoreGroup extends StatelessWidget {
  const _MoreGroup({required this.items});

  final List<_MoreItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items) ...[
          _MoreRow(item: item, onTap: () => context.push(item.route)),
          if (item != items.last) const SizedBox(height: AppSizes.xs),
        ],
      ],
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.item, required this.onTap});

  final _MoreItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          ClayIconChip(icon: item.icon, color: item.color, size: 34, iconSize: AppSizes.iconSm, glow: true),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.label, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  item.subtitle,
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
