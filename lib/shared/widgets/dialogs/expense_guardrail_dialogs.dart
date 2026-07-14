import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';

/// Guards a form's back gesture/Cancel button against silently discarding
/// dirty fields — mirrors [confirmDelete]'s shape (two choices, the
/// destructive one styled distinctly) but for "leave without saving"
/// instead of "delete". Returns `true` only if the user chose to discard;
/// `false`/`null` (dismissed) means the caller must stay on the form.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Unsaved Changes'),
      content: const Text('You have unsaved changes. Discard them?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Acknowledges an Add Payment save that didn't cover the full remaining
/// amount — informational only (the payment already saved as a partial),
/// so there's nothing to choose between, just an `OK`.
Future<void> showPartialPaymentInfo(BuildContext context, {required double remainingAmount}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.info_outline_rounded, color: Colors.blue),
      title: const Text('Partial Payment'),
      content: Text(
        'This expense is partially paid. Remaining amount: ${CurrencyFormatter.instance.format(remainingAmount)}',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Blocks a Settle Amount attempt that doesn't actually cover the full
/// remaining balance — a hard stop (single `OK`), not a choice, since the
/// only way forward is to go back and fix the entered amount/toggle.
Future<void> showCannotSettleInfo(BuildContext context, {required double remainingAmount}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.error_outline_rounded, color: Theme.of(dialogContext).colorScheme.error),
      title: const Text('Cannot Settle'),
      content: Text(
        "You haven't received the full amount yet. Remaining amount: ${CurrencyFormatter.instance.format(remainingAmount)}",
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
