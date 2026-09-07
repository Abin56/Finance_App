import 'package:flutter/material.dart';

import '../../../features/expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../features/paste_import/presentation/screens/paste_import_screen.dart';
import '../../../features/smart_import/presentation/screens/smart_import_screen.dart';
import '../../../features/transactions/presentation/screens/add_expense_screen.dart';
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
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Smart Import'),
            subtitle: const Text('Scan a screenshot or use your camera'),
            onTap: () => Navigator.of(sheetContext).pop('smart_import'),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_rounded),
            title: const Text('Paste Transactions'),
            subtitle: const Text('Paste copied transaction information'),
            onTap: () => Navigator.of(sheetContext).pop('paste_import'),
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
  } else if (choice == 'smart_import') {
    await SmartImportScreen.show(context);
  } else if (choice == 'paste_import') {
    await PasteImportScreen.show(context);
  } else {
    await AddExpenseScreen.show(context);
  }
}
