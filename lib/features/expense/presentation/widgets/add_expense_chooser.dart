import 'package:flutter/material.dart';

import '../../../people/domain/person.dart';
import 'assign_expense_sheet.dart';
import 'split_expense_form_sheet.dart';

/// The "+ Add Expense" entry point used by the Contact Ledger
/// (`PersonStatementScreen`) and [AddExpenseScreen]'s "Share Expense" row —
/// a two-choice bottom sheet (share with several people vs. assign the whole
/// thing to one person) funnelling into the same
/// [SplitExpenseFormSheet]/[AssignExpenseSheet] the screen already used, so
/// there's exactly one "add a shared expense" flow in the app.
abstract class AddExpenseChooser {
  AddExpenseChooser._();

  /// [forPerson] is set when opened from that person's own Contact Ledger
  /// screen — the person is already known from context, so both flows below
  /// pre-fill it instead of asking the user to pick it again. [draft] is set
  /// when opened from [AddExpenseScreen] instead, carrying over the
  /// in-progress form so the user never re-types what they already entered.
  /// Resolves to `true` only when the chosen sheet actually saved.
  static Future<bool?> show(BuildContext context, {Person? forPerson, AddExpenseDraftPrefill? draft}) async {
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
    if (!context.mounted || choice == null) return null;
    if (choice == 'split') {
      return SplitExpenseFormSheet.show(context, initialParticipant: forPerson, draft: draft);
    } else {
      return AssignExpenseSheet.show(context, initialPerson: forPerson, draft: draft);
    }
  }
}
