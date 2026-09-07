import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../features/expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../features/paste_import/presentation/screens/paste_import_screen.dart';
import '../../../features/smart_import/presentation/screens/smart_import_screen.dart';
import '../../../features/transactions/presentation/screens/add_expense_screen.dart';
import '../../../features/transactions/presentation/widgets/money_received_sheet.dart';
import '../lists/flowfi_list_tile.dart';
import '../states/flowfi_icon_chip.dart';

/// The bottom sheet behind every "add" entry point in the app (the History
/// screen's app bar action and the nav shell's central "+" button) — lets
/// the user choose which kind of entry to create instead of guessing from
/// which tab they tapped.
Future<void> showAddEntryMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowFiListTile(
              leading: const FlowFiIconChip(
                icon: Icons.add_rounded,
                color: AppColors.primary,
              ),
              title: const Text('Add transaction'),
              onTap: () => Navigator.of(sheetContext).pop('transaction'),
            ),
            FlowFiListTile(
              leading: const FlowFiIconChip(
                icon: Icons.call_split_rounded,
                color: AppColors.secondary,
              ),
              title: const Text('Share expense'),
              subtitle: const Text('Share a bill with friends or family'),
              onTap: () => Navigator.of(sheetContext).pop('split'),
            ),
            FlowFiListTile(
              leading: const FlowFiIconChip(
                icon: Icons.call_received_rounded,
                color: AppColors.income,
              ),
              title: const Text('Money received'),
              onTap: () => Navigator.of(sheetContext).pop('received'),
            ),
            FlowFiListTile(
              leading: const FlowFiIconChip(
                icon: Icons.document_scanner_outlined,
                color: AppColors.purple,
              ),
              title: const Text('Smart Import'),
              subtitle: const Text('Scan a screenshot or use your camera'),
              onTap: () => Navigator.of(sheetContext).pop('smart_import'),
            ),
            FlowFiListTile(
              leading: const FlowFiIconChip(
                icon: Icons.content_paste_rounded,
                color: AppColors.info,
              ),
              title: const Text('Paste Transactions'),
              subtitle: const Text('Paste copied transaction information'),
              onTap: () => Navigator.of(sheetContext).pop('paste_import'),
            ),
          ],
        ),
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
