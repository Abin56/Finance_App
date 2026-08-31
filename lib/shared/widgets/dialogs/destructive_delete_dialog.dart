import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';

/// One line of the "this will permanently delete" impact list — only rows
/// with [count] > 0 are ever rendered.
class DestructiveDeleteImpactRow {
  const DestructiveDeleteImpactRow({required this.label, required this.count});

  final String label;
  final int count;
}

/// Serious, type-to-confirm warning for an irreversible cascade delete — the
/// Account/Credit Card "permanently delete from Trash" moment, which now
/// wipes every transaction/bill/shared-expense effect linked to the entity
/// (see `account_deletion_service.dart`/`credit_card_deletion_service.dart`)
/// instead of leaving them orphaned. Unlike [confirmDelete]/
/// `delete_confirmation_dialog.dart`'s plain soft-delete confirmation, this
/// shows exactly what will be destroyed and requires typing the entity's own
/// name before the destructive action becomes reachable.
///
/// Use [showDestructiveDeleteDialog] rather than constructing this directly.
class DestructiveDeleteDialog extends StatefulWidget {
  const DestructiveDeleteDialog({
    super.key,
    required this.entityLabel,
    required this.entityName,
    required this.loadImpact,
    required this.onConfirm,
  });

  /// e.g. "account" or "credit card" — used in the warning copy.
  final String entityLabel;
  final String entityName;
  final Future<List<DestructiveDeleteImpactRow>> Function() loadImpact;
  final Future<void> Function() onConfirm;

  @override
  State<DestructiveDeleteDialog> createState() => _DestructiveDeleteDialogState();
}

class _DestructiveDeleteDialogState extends State<DestructiveDeleteDialog> {
  final _controller = TextEditingController();
  List<DestructiveDeleteImpactRow>? _impact;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.loadImpact().then((impact) {
      if (mounted) setState(() => _impact = impact);
    });
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canConfirm => !_confirming && _impact != null && _controller.text.trim() == widget.entityName;

  Future<void> _handleConfirm() async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleImpact = (_impact ?? const []).where((row) => row.count > 0).toList();

    return PopScope(
      canPop: !_confirming,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusLg)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: AppSizes.sm),
            Expanded(child: Text('Permanently delete ${widget.entityName}?')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This cannot be undone. Deleting this ${widget.entityLabel} permanently erases '
                'its entire history — it is not moved to Trash.',
              ),
              const SizedBox(height: AppSizes.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSizes.md),
                decoration: BoxDecoration(color: colorScheme.errorContainer.withValues(alpha: 0.35)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will permanently delete:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.error),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    if (_impact == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSizes.xs),
                        child: LinearProgressIndicator(),
                      )
                    else if (visibleImpact.isEmpty)
                      Text(
                        'Nothing else is linked to this ${widget.entityLabel}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      for (final row in visibleImpact)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('•  ${row.label}'),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Text.rich(
                TextSpan(
                  text: 'Type ',
                  children: [
                    TextSpan(text: widget.entityName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' to confirm'),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              TextField(
                controller: _controller,
                enabled: !_confirming,
                autofocus: true,
                decoration: InputDecoration(hintText: widget.entityName, border: const OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSizes.sm),
                Text(_error!, style: TextStyle(color: colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _confirming ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canConfirm ? _handleConfirm : null,
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            child: _confirming
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onError),
                  )
                : const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
}

/// Shows [DestructiveDeleteDialog] and returns `true` only if the user
/// completed the delete; `false`/`null` (dismissed/cancelled) means the
/// caller must not treat anything as deleted.
Future<bool> showDestructiveDeleteDialog(
  BuildContext context, {
  required String entityLabel,
  required String entityName,
  required Future<List<DestructiveDeleteImpactRow>> Function() loadImpact,
  required Future<void> Function() onConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DestructiveDeleteDialog(
      entityLabel: entityLabel,
      entityName: entityName,
      loadImpact: loadImpact,
      onConfirm: onConfirm,
    ),
  );
  return result ?? false;
}
