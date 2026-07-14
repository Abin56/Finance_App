import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';

/// Everything the old two-pane dashboard surfaced inline (Lending, EMI,
/// Savings, Bills, Accounts, Budget) now lives one tap away behind "More" —
/// the Figma dashboard's quick-actions row has no room for a whole section
/// per feature, so this sheet keeps every route reachable without cluttering
/// the linear layout.
class MoreActionsSheet extends StatelessWidget {
  const MoreActionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MoreActionsSheet(),
    );
  }

  static const _items = [
    _MoreItem(icon: Icons.handshake_outlined, label: 'Lending', route: AppRoutes.loans),
    _MoreItem(icon: Icons.calendar_month_outlined, label: 'Monthly EMI', route: AppRoutes.emis),
    _MoreItem(icon: Icons.savings_outlined, label: 'Savings', route: AppRoutes.savings),
    _MoreItem(icon: Icons.receipt_long_outlined, label: 'Bills', route: AppRoutes.bills),
    _MoreItem(icon: Icons.credit_card_outlined, label: 'Credit Cards', route: AppRoutes.creditCards),
    _MoreItem(icon: Icons.account_balance_outlined, label: 'Accounts', route: AppRoutes.accounts),
    _MoreItem(icon: Icons.donut_large_rounded, label: 'Budget', route: AppRoutes.budget),
    _MoreItem(icon: Icons.category_outlined, label: 'Categories', route: AppRoutes.categories),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in _items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(item.route);
                },
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
