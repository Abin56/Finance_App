import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/loan.dart';
import '../../domain/loan_origination.dart';
import '../providers/loan_providers.dart';

/// Confirmation for "Reverse & Delete" — undoing a unified-wizard Loan's
/// creation, including the money it recorded. [message] states the real
/// Account effect (see [originationReversalMessage]).
Future<bool> confirmReverseOrigination(
  BuildContext context, {
  required String loanName,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Reverse & Delete $loanName?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text(
              "The agreement moves to Trash and its recorded money movement is undone. It can't be restored afterwards — add it again if needed.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reverse & Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// For a Loan whose origination money is still active, runs the whole
/// "Reverse & Delete" flow and returns true (the caller must NOT also trash
/// it). Returns false for every other Loan, which keeps its plain delete.
Future<bool> reverseOriginationIfMoneyActive(
  BuildContext context,
  WidgetRef ref,
  Loan loan,
) async {
  final repository = ref.read(loanRepositoryProvider);
  final movement = await repository.activeOriginationMovement(loan);
  final key = originationKeyFromLoanId(loan.id);
  if (movement == null || key == null) return false;
  final account = await ref
      .read(accountRepositoryProvider)
      .getByKey(movement.accountId);
  if (!context.mounted) return true;
  final confirmed = await confirmReverseOrigination(
    context,
    loanName: loan.name?.trim().isNotEmpty == true ? loan.name!.trim() : 'loan',
    message: originationReversalMessage((
      kind: movement.kind,
      amount: movement.amount,
      accountName: account?.name ?? 'the account',
    )),
  );
  if (!confirmed || !context.mounted) return true;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repository.reverseOrigination(key);
    messenger.showSnackBar(
      const SnackBar(content: Text('Loan creation reversed')),
    );
  } on AppException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
  return true;
}
