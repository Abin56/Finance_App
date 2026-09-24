import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../features/expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../features/paste_import/presentation/screens/paste_import_screen.dart';
import '../../../features/pdf_import/presentation/screens/pdf_import_screen.dart';
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
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add new',
            style: Theme.of(
              sheetContext,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.md),
          _EntryOption(
            icon: Icons.add_rounded,
            color: AppColors.primary,
            title: 'Add transaction',
            subtitle: 'Log an expense or income entry',
            onTap: () => Navigator.of(sheetContext).pop('transaction'),
          ),
          _EntryOption(
            icon: Icons.call_received_rounded,
            color: AppColors.income,
            title: 'Money received',
            subtitle: 'Record money someone paid you back',
            onTap: () => Navigator.of(sheetContext).pop('received'),
          ),
          _EntryOption(
            icon: Icons.call_split_rounded,
            color: AppColors.secondary,
            title: 'Share expense',
            subtitle: 'Split a bill with friends or family',
            onTap: () => Navigator.of(sheetContext).pop('split'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.sm),
            child: Divider(height: 1),
          ),
          _EntryOption(
            icon: Icons.document_scanner_outlined,
            color: AppColors.purple,
            title: 'Smart Import',
            subtitle: 'Scan a screenshot or use your camera',
            onTap: () => Navigator.of(sheetContext).pop('smart_import'),
          ),
          _EntryOption(
            icon: Icons.content_paste_rounded,
            color: AppColors.info,
            title: 'Paste Transactions',
            subtitle: 'Paste copied transaction text',
            onTap: () => Navigator.of(sheetContext).pop('paste_import'),
          ),
          _EntryOption(
            icon: Icons.picture_as_pdf_outlined,
            color: AppColors.expense,
            title: 'PDF Statement',
            subtitle: 'Import transactions from a bank statement PDF',
            onTap: () => Navigator.of(sheetContext).pop('pdf_import'),
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
  } else if (choice == 'pdf_import') {
    await PdfImportScreen.show(context);
  } else {
    await AddExpenseScreen.show(context);
  }
}

/// One tappable row in the add-entry sheet — a larger icon chip, title +
/// helper subtitle, and a trailing chevron so every row reads clearly as
/// its own tappable action rather than plain list text.
class _EntryOption extends StatelessWidget {
  const _EntryOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FlowFiListTile(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: AppSizes.md,
      ),
      leading: FlowFiIconChip(icon: icon, color: color, size: 48),
      title: Text(
        title,
        style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: context.colors.onSurface.withValues(alpha: 0.35),
      ),
      onTap: onTap,
    );
  }
}
