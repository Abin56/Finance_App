import 'package:flutter/material.dart';

import '../../../accounts/presentation/screens/accounts_trash_screen.dart';
import '../../../budget/presentation/screens/budget_trash_screen.dart';
import '../../../bills/presentation/screens/bills_trash_screen.dart';
import '../../../categories/presentation/screens/categories_trash_screen.dart';
import '../../../emi/presentation/screens/emis_trash_screen.dart';
import '../../../lending/presentation/screens/loans_trash_screen.dart';
import '../../../people/presentation/screens/people_trash_screen.dart';
import '../../../savings/presentation/screens/savings_trash_screen.dart';
import '../../../transactions/presentation/screens/transactions_trash_screen.dart';

/// A single entry point to every feature's existing trash screen — pure
/// navigation glue, reusing each feature's own soft-delete trash screen
/// and stream rather than introducing a unified trash provider/model.
class TrashHubScreen extends StatelessWidget {
  const TrashHubScreen({super.key});

  static final _items = [
    _TrashItem(icon: Icons.receipt_long_outlined, label: 'Transactions', builder: (_) => const TransactionsTrashScreen()),
    _TrashItem(icon: Icons.account_balance_wallet_outlined, label: 'Accounts', builder: (_) => const AccountsTrashScreen()),
    _TrashItem(icon: Icons.category_outlined, label: 'Categories', builder: (_) => const CategoriesTrashScreen()),
    _TrashItem(icon: Icons.donut_large_outlined, label: 'Budget', builder: (_) => const BudgetTrashScreen()),
    _TrashItem(icon: Icons.receipt_outlined, label: 'Bills', builder: (_) => const BillsTrashScreen()),
    _TrashItem(icon: Icons.calendar_month_outlined, label: 'EMIs', builder: (_) => const EmisTrashScreen()),
    _TrashItem(icon: Icons.handshake_outlined, label: 'Loans', builder: (_) => const LoansTrashScreen()),
    _TrashItem(icon: Icons.savings_outlined, label: 'Savings Goals', builder: (_) => const SavingsTrashScreen()),
    _TrashItem(icon: Icons.people_outline_rounded, label: 'People', builder: (_) => const PeopleTrashScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: ListView(
        children: [
          for (final item in _items)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: item.builder)),
            ),
        ],
      ),
    );
  }
}

class _TrashItem {
  const _TrashItem({required this.icon, required this.label, required this.builder});

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}
