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
  static const _financeItems = [
    _MoreItem(icon: Icons.pie_chart_outline_rounded, label: 'Reports', route: AppRoutes.reports, color: Color(0xFF615FFF)),
    _MoreItem(icon: Icons.credit_card_outlined, label: 'Credit Cards', route: AppRoutes.creditCards, color: AppColors.purple),
    _MoreItem(icon: Icons.savings_outlined, label: 'Savings Goals', route: AppRoutes.savings, color: AppColors.savings),
    _MoreItem(icon: Icons.category_outlined, label: 'Categories', route: AppRoutes.categories, color: AppColors.secondary),
  ];

  static const _appItems = [
    _MoreItem(icon: Icons.settings_outlined, label: 'Settings', route: AppRoutes.settings, color: Color(0xFF64748B)),
    _MoreItem(icon: Icons.cloud_upload_outlined, label: 'Backup & Restore', route: AppRoutes.comingSoon, color: AppColors.info),
    _MoreItem(icon: Icons.delete_outline_rounded, label: 'Trash', route: AppRoutes.trash, color: AppColors.error),
    _MoreItem(icon: Icons.info_outline_rounded, label: 'About', route: AppRoutes.about, color: AppColors.primary),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(title: const Text('More')),
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
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Text(
              _initials,
              style: context.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppSizes.md),
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
  const _MoreItem({required this.icon, required this.label, required this.route, required this.color});

  final IconData icon;
  final String label;
  final String route;
  final Color color;
}

/// One labeled group of menu rows — reads as a single grouped surface
/// rather than one floating card per row, which would feel heavy on a
/// small phone.
class _MoreGroup extends StatelessWidget {
  const _MoreGroup({required this.items});

  final List<_MoreItem> items;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items) ...[
            _MoreRow(item: item, onTap: () => context.push(item.route)),
            if (item != items.last) Divider(height: 1, indent: AppSizes.lg + 40 + AppSizes.md, color: context.colors.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.item, required this.onTap});

  final _MoreItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClayPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
        child: Row(
          children: [
            ClayIconChip(icon: item.icon, color: item.color, size: 40, iconSize: AppSizes.iconSm),
            const SizedBox(width: AppSizes.md),
            Expanded(child: Text(item.label, style: context.textTheme.bodyLarge)),
            Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
