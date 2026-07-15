import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';

/// Bottom action bar shown once the user long-presses into multi-select
/// mode. Every action works on any selection size: one selected SMS opens the
/// full convert sheet, several open the bulk sheet (shared answers once, one
/// transaction each — see `SmsBulkConverter`).
///
/// Actions are icon-only with tooltips: at 360dp four labelled buttons plus
/// the "N selected" count overflow the row.
class SmsMultiSelectToolbar extends StatelessWidget {
  const SmsMultiSelectToolbar({
    super.key,
    required this.selectedCount,
    required this.onConvert,
    required this.onIgnore,
    required this.onDelete,
    required this.onSelectAll,
    required this.onCancel,
  });

  final int selectedCount;

  /// Never null now that bulk convert exists — kept nullable only so a caller
  /// can disable it while a conversion is already running.
  final VoidCallback? onConvert;
  final VoidCallback onIgnore;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainerHighest,
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(onPressed: onCancel, icon: const Icon(Icons.close_rounded), tooltip: 'Cancel'),
              Expanded(
                child: Text(
                  '$selectedCount selected',
                  style: context.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onSelectAll,
                icon: const Icon(Icons.select_all_rounded),
                tooltip: 'Select all',
              ),
              IconButton(
                onPressed: onConvert,
                icon: const Icon(Icons.bolt_rounded),
                tooltip: selectedCount == 1 ? 'Convert' : 'Convert all',
              ),
              IconButton(
                onPressed: onIgnore,
                icon: const Icon(Icons.visibility_off_outlined),
                tooltip: 'Ignore',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
