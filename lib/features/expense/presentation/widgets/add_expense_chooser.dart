import 'package:flutter/material.dart';

import 'assign_expense_sheet.dart';
import 'split_expense_form_sheet.dart';

/// The "+ Add Expense" entry point shared by [ExpensesScreen] and the
/// Contact Ledger (`PersonStatementScreen`) — a two-choice bottom sheet
/// (share with several people vs. assign the whole thing to one person)
/// funnelling into the same [SplitExpenseFormSheet]/[AssignExpenseSheet]
/// either screen already used, so there's exactly one "add a shared
/// expense" flow in the app, not a third copy per entry point.
abstract class AddExpenseChooser {
  AddExpenseChooser._();

  static Future<void> show(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_split_rounded),
              title: const Text('Share with several people'),
              onTap: () => Navigator.of(sheetContext).pop('split'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('This person will pay'),
              onTap: () => Navigator.of(sheetContext).pop('assign'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'split') {
      await SplitExpenseFormSheet.show(context);
    } else {
      await AssignExpenseSheet.show(context);
    }
  }
}
