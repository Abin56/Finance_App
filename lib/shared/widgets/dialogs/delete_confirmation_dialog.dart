import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// Task 3's "confirm before delete" dialog — one shared helper every
/// swipe-to-dismiss/delete action in the app calls before it soft-deletes,
/// so the wording and behavior are identical everywhere (Transactions,
/// Split Expenses, People, Loans, Bills, EMI, Budget, Savings). Soft-delete
/// itself is unchanged: confirming here just lets the caller's existing
/// softDelete + "Undo" snackbar flow proceed as it already did.
///
/// Returns `true` only if the user tapped Delete; `false`/`null` (dismissed)
/// means the caller must not delete anything — for a [Dismissible]'s
/// `confirmDismiss`, returning anything but `true` snaps the tile back into
/// place.
Future<bool> confirmDelete(
  BuildContext context, {
  required String entityName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete $entityName?'),
      content: const Text(
        'This action moves it to Trash. You can restore it later.',
      ),
      actions: [
        AppDialogActions.cancel(dialogContext),
        AppDialogActions.destructive(dialogContext),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Which action the user chose in [confirmDeleteWithPermanentOption].
enum DeleteChoice { cancel, trash, permanent }

/// Same swipe-to-delete moment as [confirmDelete], but offers a second,
/// less-reversible path straight from the list: "Delete Permanently" skips
/// Trash entirely, alongside the usual "Move to Trash". Used only where a
/// caller explicitly wants that shortcut (currently History's transaction
/// list) — everywhere else keeps the single Trash-only [confirmDelete] flow.
Future<DeleteChoice> confirmDeleteWithPermanentOption(
  BuildContext context, {
  required String entityName,
}) async {
  final choice = await showDialog<DeleteChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete $entityName?'),
      content: const Text(
        'Move it to Trash (you can restore it later), or delete it permanently right away — this can\'t be undone.',
      ),
      actions: [
        AppDialogActions.cancel(
          dialogContext,
          onPressed: () => Navigator.of(dialogContext).pop(DeleteChoice.cancel),
        ),
        AppDialogActions.destructive(
          dialogContext,
          label: 'Delete Permanently',
          onPressed: () =>
              Navigator.of(dialogContext).pop(DeleteChoice.permanent),
        ),
        AppDialogActions.confirm(
          dialogContext,
          label: 'Move to Trash',
          onPressed: () => Navigator.of(dialogContext).pop(DeleteChoice.trash),
        ),
      ],
    ),
  );
  return choice ?? DeleteChoice.cancel;
}
