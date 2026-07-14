import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';

/// The "More" tab — secondary destinations that don't need their own
/// bottom-nav slot: Reports (analysis, kept deliberately separate from the
/// Cash Flow tab's planning focus), Settings, Credit Cards, Savings Goals,
/// Categories, Backup & Restore, Trash, and About.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _items = [
    _MoreItem(icon: Icons.pie_chart_outline_rounded, label: 'Reports', route: AppRoutes.reports),
    _MoreItem(icon: Icons.settings_outlined, label: 'Settings', route: AppRoutes.settings),
    _MoreItem(icon: Icons.credit_card_outlined, label: 'Credit Cards', route: AppRoutes.creditCards),
    _MoreItem(icon: Icons.savings_outlined, label: 'Savings Goals', route: AppRoutes.savings),
    _MoreItem(icon: Icons.category_outlined, label: 'Categories', route: AppRoutes.categories),
    _MoreItem(icon: Icons.cloud_upload_outlined, label: 'Backup & Restore', route: AppRoutes.comingSoon),
    _MoreItem(icon: Icons.delete_outline_rounded, label: 'Trash', route: AppRoutes.trash),
    _MoreItem(icon: Icons.info_outline_rounded, label: 'About', route: AppRoutes.about),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
          children: [
            for (final item in _items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(item.route),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;
}
