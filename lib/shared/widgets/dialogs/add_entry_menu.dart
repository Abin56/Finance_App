import 'package:flutter/material.dart';

import '../../../features/expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../features/transactions/presentation/screens/add_expense_screen.dart';
import '../../../features/transactions/presentation/screens/transfer_screen.dart';
import '../../../features/transactions/presentation/widgets/money_received_sheet.dart';

/// The bottom sheet behind every "add" entry point in the app (the History
/// screen's app bar action and the nav shell's central "+" button) — lets
/// the user choose which kind of entry to create instead of guessing from
/// which tab they tapped.
Future<void> showAddEntryMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('Add transaction'),
            onTap: () => Navigator.of(sheetContext).pop('transaction'),
          ),
          ListTile(
            leading: const Icon(Icons.call_split_rounded),
            title: const Text('Share expense'),
            subtitle: const Text('Share a bill with friends or family'),
            onTap: () => Navigator.of(sheetContext).pop('split'),
          ),
          ListTile(
            leading: const Icon(Icons.call_received_rounded),
            title: const Text('Money received'),
            onTap: () => Navigator.of(sheetContext).pop('received'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Transfer between accounts'),
            subtitle: const Text('Move money between two of your own accounts'),
            onTap: () => Navigator.of(sheetContext).pop('transfer'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'received') {
    await MoneyReceivedSheet.show(context);
  } else if (choice == 'split') {
    await SplitExpenseFormSheet.show(context);
  } else if (choice == 'transfer') {
    await TransferScreen.show(context);
  } else {
    await AddExpenseScreen.show(context);
  }
}
