import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';

/// Every split/assigned-expense participant record for one person — pending
/// or already settled — so a single watch can resolve both "Mark as
/// Settled" (remaining > 0) and "View settlement" (remaining == 0) cases for
/// a [PersonTimelineEntry] on that person's statement. Built the same way as
/// [pendingSplitParticipantsProvider], scoped to [personId], without that
/// provider's remaining-amount filter. Skips `participant.isMe` (no
/// installment tracks the payer's own share, mirrors
/// `_ParticipantCard`'s null-safety on `TransactionDetailScreen`).
final personSplitParticipantsProvider =
    Provider.autoDispose.family<List<PendingSplitParticipant>, String>((ref, personId) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  final result = <PendingSplitParticipant>[];
  for (final expense in expenses) {
    if (!expense.isSplit || expense.scheduleId == null) continue;
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final installmentsById = {for (final i in installments) i.id: i};
    for (final participant in expense.participants) {
      if (participant.isMe || participant.personId != personId) continue;
      final installment = installmentsById[participant.installmentId];
      if (installment == null) continue;
      result.add((expense: expense, participant: participant, installment: installment));
    }
  }
  return result;
});
