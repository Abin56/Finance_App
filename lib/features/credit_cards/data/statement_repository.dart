import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/services/reminder_notification_service.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/reminder_offset_label.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/credit_card_profile.dart';
import '../domain/statement.dart';
import '../domain/statement_period.dart';

/// Statement persistence, built around "lazy generation" — this app has no
/// background jobs, so a statement is never created by a timer. Instead:
/// [currentCycleFor] computes the in-progress cycle's totals live, purely
/// from already-loaded transactions (no write, nothing persisted), and
/// [materializeIfDue] is called by the provider layer whenever a card's
/// screen is opened — it writes exactly one `Statement` document the first
/// time a closed cycle is actually viewed, then never touches that
/// document's `totalAmount` again. Because of that, [totalFor] must also be
/// used to recompute a *closed* statement's true current total on every
/// read (see `statementsWithLiveTotalsProvider`) — a transaction dated
/// inside an already-materialized period can still be deleted/edited/
/// restored afterward, and only recomputing from live transactions (the
/// same way [currentCycleFor] already does for the open cycle) keeps that
/// reflected everywhere, since the stored document is never rewritten.
class StatementRepository extends FirestoreCrudRepository<Statement> {
  StatementRepository(super.collection);

  /// Sums [cardTransactions] whose `dateTime` falls within [period] —
  /// the one true definition of a statement period's total, used both to
  /// materialize a new statement and to correct an existing one's total at
  /// read time when transactions inside it have since changed.
  double totalFor(List<Transaction> cardTransactions, StatementPeriod period) {
    return cardTransactions
        .where((t) => !t.isDeleted && period.contains(t.dateTime))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// The in-progress (not yet closed) cycle's live totals — an ephemeral,
  /// unsaved [Statement] (`id: 'current'`) for display only. Never written
  /// to Firestore; recomputed on every call.
  Statement currentCycleFor(CreditCardProfile card, List<Transaction> cardTransactions, {DateTime? now}) {
    final period = StatementPeriodCalculator.currentCycleFor(card, now: now);
    return Statement(
      id: 'current',
      cardId: card.id,
      periodStart: period.periodStart,
      periodEnd: period.periodEnd,
      generatedDate: period.periodEnd,
      dueDate: period.dueDate,
      totalAmount: totalFor(cardTransactions, period),
      minimumDue: card.minimumDuePercent == null
          ? null
          : totalFor(cardTransactions, period) * card.minimumDuePercent! / 100,
      createdAt: now ?? DateTime.now(),
    );
  }

  /// If the most recently closed cycle (per [StatementPeriodCalculator])
  /// has no matching [Statement] document yet, creates one from
  /// [cardTransactions] in that exact window and schedules its due-date
  /// reminders. Returns null when nothing new needs materializing (already
  /// exists, or the first cycle hasn't closed yet). Safe to call on every
  /// screen open — idempotent, since it only ever acts on the single most
  /// recently closed cycle and checks [existing] first.
  Future<Statement?> materializeIfDue(
    CreditCardProfile card,
    List<Transaction> cardTransactions,
    List<Statement> existing, {
    DateTime? now,
  }) async {
    final period = StatementPeriodCalculator.mostRecentClosedCycleFor(card, now: now);
    final today = DateTime(
      (now ?? DateTime.now()).year,
      (now ?? DateTime.now()).month,
      (now ?? DateTime.now()).day,
    );
    if (period.periodEnd.isAfter(today)) return null;

    final alreadyExists = existing.any(
      (s) => s.periodStart.isAtSameMomentAs(period.periodStart) && s.periodEnd.isAtSameMomentAs(period.periodEnd),
    );
    if (alreadyExists) return null;

    final total = totalFor(cardTransactions, period);
    // Nothing to materialize — a cycle with zero purchases (e.g. a card
    // that was just added and has no history yet) shouldn't spam an empty
    // statement document every time the screen opens.
    if (total <= 0) return null;

    final statement = Statement(
      id: IdGenerator.generate(),
      cardId: card.id,
      periodStart: period.periodStart,
      periodEnd: period.periodEnd,
      generatedDate: period.periodEnd,
      dueDate: period.dueDate,
      totalAmount: total,
      minimumDue: card.minimumDuePercent == null ? null : total * card.minimumDuePercent! / 100,
      createdAt: DateTime.now(),
    );
    await add(statement.id, statement);
    _scheduleReminders(statement);
    return statement;
  }

  /// Best-effort, fire-and-forget — mirrors [BillRepository]'s reminder
  /// scheduling; a notification failure must never block a Firestore write.
  void _scheduleReminders(Statement statement) {
    ReminderNotificationService.reschedule(
      ownerId: statement.id,
      title: 'Credit card statement',
      bodyBuilder: (offset) =>
          '${reminderOffsetLabel(offset)} — pay by ${statement.dueDate.day}/${statement.dueDate.month}',
      dueDate: statement.dueDate,
      offsets: const [7, 1, 0],
    ).catchError((_) {});
  }

  /// Updates [statement]'s manually-logged [Statement.interestCharged]/
  /// [Statement.lateFee] — the only fields a statement supports editing
  /// after generation (mirrors [CreditCardRepository.editCard]'s
  /// clear-vs-update pattern for nullable fields, since these amounts are
  /// user-entered, not computed, and can legitimately be corrected or
  /// removed). Never touches [Statement.totalAmount] — that stays a closed
  /// snapshot of the billing cycle's transactions.
  Future<void> editStatement(
    Statement statement, {
    double? interestCharged,
    bool clearInterestCharged = false,
    double? lateFee,
    bool clearLateFee = false,
  }) async {
    if (clearInterestCharged) {
      statement.recordEdit(
        field: 'interestCharged',
        oldValue: statement.interestCharged?.toString() ?? 'none',
        newValue: 'none',
      );
      statement.interestCharged = null;
    } else {
      statement.updateField(
        field: 'interestCharged',
        oldValue: statement.interestCharged,
        newValue: interestCharged,
        apply: (v) => statement.interestCharged = v,
      );
    }

    if (clearLateFee) {
      statement.recordEdit(
        field: 'lateFee',
        oldValue: statement.lateFee?.toString() ?? 'none',
        newValue: 'none',
      );
      statement.lateFee = null;
    } else {
      statement.updateField(
        field: 'lateFee',
        oldValue: statement.lateFee,
        newValue: lateFee,
        apply: (v) => statement.lateFee = v,
      );
    }

    await update(statement);
  }

  /// Applies a payment delta toward [statement], clamped so [amountPaid]
  /// never exceeds [totalAmount] — mirrors [BillRepository.applyPayment].
  Future<void> applyPayment(Statement statement, double delta) async {
    if (delta == 0) return;
    final newAmountPaid = (statement.amountPaid + delta).clamp(0, statement.totalAmount).toDouble();
    statement.recordEdit(
      field: 'amountPaid',
      oldValue: statement.amountPaid.toString(),
      newValue: newAmountPaid.toString(),
    );
    statement.amountPaid = newAmountPaid;
    await update(statement);
  }
}
