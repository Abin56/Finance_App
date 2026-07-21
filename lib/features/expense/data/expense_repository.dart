import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/payment_schedule/data/installment_payment_repository.dart';
import '../../../core/payment_schedule/data/installment_repository.dart';
import '../../../core/payment_schedule/data/payment_schedule_repository.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/owner_type.dart';
import '../../../core/payment_schedule/domain/precomputed_installment_amount.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../core/utils/id_generator.dart';
import '../../people/data/ledger_repository.dart';
import '../../people/data/person_repository.dart';
import '../../people/domain/ledger_entry.dart';
import '../../people/domain/ledger_entry_type.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/expense.dart';
import '../domain/expense_participant.dart';
import '../domain/split_type.dart';

/// A single participant's raw input before shares are resolved — the UI
/// layer supplies these; [ExpenseRepository] computes the actual [share]
/// each participant owes according to [SplitType].
class ExpenseParticipantInput {
  const ExpenseParticipantInput({
    required this.name,
    this.personId,
    this.value,
    this.isMe = false,
  });

  final String? personId;
  final String name;

  /// Meaningful only for [SplitType.custom] (exact amount) and
  /// [SplitType.percentage] (0-100). Ignored for [SplitType.equal].
  final double? value;

  /// Whether this input represents the permanent "Me" participant — see
  /// [ExpenseParticipant.isMe].
  final bool isMe;
}

/// Expense-specific persistence, bridging the feature-agnostic
/// `PaymentScheduleRepository`/`InstallmentRepository` (participant
/// settlement tracking via `OwnerType.splitExpense`), `TransactionRepository`
/// (account balance effect), and `LedgerRepository` (per-person pending
/// balance) — mirrors how `EmiRepository` composes the same schedule engine
/// with `InterestCalculator`. No new financial math is invented here beyond
/// dividing [Expense.totalAmount] into participant shares.
class ExpenseRepository extends FirestoreCrudRepository<Expense> {
  ExpenseRepository(
    super.collection,
    this.transactionRepository,
    this.paymentScheduleRepository,
    this.personRepository,
    this._installmentRepositoryFor,
    this._ledgerRepositoryFor,
  );

  final TransactionRepository transactionRepository;
  final PaymentScheduleRepository paymentScheduleRepository;
  final PersonRepository personRepository;

  /// Resolves an `InstallmentRepository` scoped to a given schedule id —
  /// supplied by the provider layer, mirrors `EmiRepository`'s dependency shape.
  final InstallmentRepository Function(String scheduleId) _installmentRepositoryFor;

  /// Resolves a `LedgerRepository` scoped to a given person id.
  final LedgerRepository Function(String personId) _ledgerRepositoryFor;

  /// Resolves [inputs] into each participant's positive [share] of [total]
  /// according to [type], validating that the shares add up. Unlimited
  /// participants are supported — no cap on [inputs].length.
  static List<ExpenseParticipant> resolveShares({
    required SplitType type,
    required double total,
    required List<ExpenseParticipantInput> inputs,
  }) {
    if (inputs.isEmpty) {
      throw const AppException('A shared expense needs at least one person');
    }

    // Reject the same person appearing twice (by tracked id, or by name for
    // free-text participants) so shares can't be silently double-counted.
    final seenPersonIds = <String>{};
    final seenNames = <String>{};
    for (final input in inputs) {
      if (input.personId != null && !seenPersonIds.add(input.personId!)) {
        throw AppException('${input.name} is already in this split');
      }
      final nameKey = input.name.trim().toLowerCase();
      if (nameKey.isNotEmpty && input.personId == null && !seenNames.add(nameKey)) {
        throw AppException('${input.name} is already in this split');
      }
    }

    switch (type) {
      case SplitType.none:
        return const [];

      case SplitType.equal:
        final share = _round2(total / inputs.length);
        final shares = List.filled(inputs.length, share, growable: true);
        final remainder = _round2(total - share * inputs.length);
        shares[shares.length - 1] = _round2(shares.last + remainder);
        return [
          for (var i = 0; i < inputs.length; i++)
            ExpenseParticipant(
              personId: inputs[i].personId,
              name: inputs[i].name,
              share: shares[i],
              isMe: inputs[i].isMe,
            ),
        ];

      case SplitType.custom:
        final participants = [
          for (final input in inputs)
            ExpenseParticipant(
              personId: input.personId,
              name: input.name,
              share: _requireValue(input, 'a custom amount'),
              isMe: input.isMe,
            ),
        ];
        final sum = _round2(participants.fold(0.0, (s, p) => s + p.share));
        if (sum != _round2(total)) {
          throw AppException(
            'Custom amounts add up to $sum, but the expense total is ${_round2(total)}. '
            'Amount left to assign: ${_round2(total - sum)}',
          );
        }
        return participants;

      case SplitType.percentage:
        final totalPercent = _round2(inputs.fold(0.0, (s, i) => s + _requireValue(i, 'a percentage')));
        if (totalPercent != 100) {
          throw AppException(
            'Percentages add up to $totalPercent%, but must total 100%. '
            'Percentage left to assign: ${_round2(100 - totalPercent)}%',
          );
        }
        final shares = inputs.map((i) => _round2(total * (i.value! / 100))).toList();
        final roundingRemainder = _round2(total - shares.fold(0.0, (s, v) => s + v));
        shares[shares.length - 1] = _round2(shares.last + roundingRemainder);
        return [
          for (var i = 0; i < inputs.length; i++)
            ExpenseParticipant(
              personId: inputs[i].personId,
              name: inputs[i].name,
              share: shares[i],
              isMe: inputs[i].isMe,
            ),
        ];
    }
  }

  /// Requires a non-negative value — zero is allowed (e.g. Part 1's "person
  /// owes the full amount" case, where the payer's own custom share is
  /// legitimately 0), only a missing or negative value is rejected.
  static double _requireValue(ExpenseParticipantInput input, String what) {
    final value = input.value;
    if (value == null || value < 0) {
      throw AppException('${input.name} needs $what of 0 or more');
    }
    return value;
  }

  static double _round2(double v) => (v * 100).round() / 100;

  /// Creates the `PaymentSchedule` + one `Installment` per non-"Me"
  /// participant (see [ExpenseParticipant.isMe] — nothing is ever
  /// "collected" from yourself, so Me never gets an installment), posts a
  /// `LedgerEntry` for each person-linked participant, and returns the full
  /// [participants] list with `installmentId`s filled in for everyone
  /// except Me. Shared by [createExpense] and [convertToSplit] — both need
  /// the exact same schedule/installment/ledger sequence, only the
  /// transaction-creation step around it differs.
  Future<(String scheduleId, List<ExpenseParticipant> participants)> _generateScheduleAndLedger({
    required String expenseId,
    required List<ExpenseParticipant> participants,
    required double totalAmount,
    required DateTime date,
    required String description,
    required String transactionId,
    DateTime? dueDate,
  }) async {
    final collectible = participants.where((p) => !p.isMe).toList();
    if (collectible.isEmpty) {
      throw const AppException('Add at least one other person to share with');
    }

    final schedule = await paymentScheduleRepository.createSchedule(
      ownerType: OwnerType.splitExpense,
      ownerId: expenseId,
      totalAmount: totalAmount,
      scheduleType: ScheduleType.oneTime,
      // Defaults to a week out rather than the expense's own date, so an
      // unpaid expense doesn't read Overdue the very next day — callers
      // (the Add/Split/Assign forms) can override with a real due date.
      firstDueDate: dueDate ?? date.add(const Duration(days: 7)),
      installmentCount: collectible.length,
    );

    final installments = await _installmentRepositoryFor(schedule.id).generateInstallments(
      schedule,
      precomputedAmounts: collectible.map((p) => PrecomputedInstallmentAmount(amountDue: p.share)).toList(),
    );

    var collectibleIndex = 0;
    final resolvedParticipants = [
      for (final participant in participants)
        if (participant.isMe)
          participant
        else
          participant.copyWith(installmentId: installments[collectibleIndex++].id),
    ];

    for (final participant in resolvedParticipants) {
      if (participant.personId == null) continue;
      final person = await personRepository.getByKey(participant.personId!);
      if (person == null) continue;
      await _ledgerRepositoryFor(person.id).addEntry(
        person,
        type: LedgerEntryType.gave,
        amount: participant.share,
        date: date,
        note: 'Split: $description',
        transactionRef: transactionId,
      );
    }

    return (schedule.id, resolvedParticipants);
  }

  /// Creates an expense, its account-balance-effecting [Transaction], and
  /// — when [splitType] isn't [SplitType.none] — a `PaymentSchedule` +
  /// per-participant `Installment`s tracking settlement, plus a `LedgerEntry`
  /// per person-linked participant so their pending balance updates
  /// immediately (mirrors `LedgerRepository.addEntry`'s balance-sync pattern).
  Future<Expense> createExpense({
    required String description,
    required double totalAmount,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required SplitType splitType,
    List<ExpenseParticipantInput> participantInputs = const [],
    String notes = '',
    DateTime? dueDate,
    bool excludeFromCalculations = false,
    DateTime? accountingMonth,
  }) async {
    if (description.trim().isEmpty) {
      throw const AppException('Expense description is required');
    }
    if (totalAmount <= 0) {
      throw const AppException('Total amount must be greater than 0');
    }

    var participants = resolveShares(type: splitType, total: totalAmount, inputs: participantInputs);

    final transaction = await transactionRepository.createTransaction(
      type: TransactionType.expense,
      amount: totalAmount,
      dateTime: date,
      accountId: accountId,
      categoryId: categoryId,
      notes: notes,
      excludeFromCalculations: excludeFromCalculations,
      accountingMonth: accountingMonth,
    );

    final expenseId = IdGenerator.generate();
    String? scheduleId;

    if (participants.isNotEmpty) {
      final result = await _generateScheduleAndLedger(
        expenseId: expenseId,
        participants: participants,
        totalAmount: totalAmount,
        date: date,
        description: description,
        transactionId: transaction.id,
        dueDate: dueDate,
      );
      scheduleId = result.$1;
      participants = result.$2;
    }

    final expense = Expense(
      id: expenseId,
      description: description,
      totalAmount: totalAmount,
      date: date,
      categoryId: categoryId,
      accountId: accountId,
      transactionId: transaction.id,
      splitType: splitType,
      participants: participants,
      scheduleId: scheduleId,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await add(expense.id, expense);
    return expense;
  }

  /// Task 2's "assign expense to person" — the degenerate single-participant
  /// case of [createExpense] (one participant owing 100% of the total), so
  /// it reuses the same split engine rather than a separate code path.
  Future<Expense> assignToPerson({
    required String description,
    required double totalAmount,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required String personId,
    required String personName,
    String notes = '',
    DateTime? dueDate,
    bool excludeFromCalculations = false,
    DateTime? accountingMonth,
  }) {
    return createExpense(
      description: description,
      totalAmount: totalAmount,
      date: date,
      categoryId: categoryId,
      accountId: accountId,
      splitType: SplitType.custom,
      participantInputs: [
        ExpenseParticipantInput(personId: personId, name: personName, value: totalAmount),
      ],
      notes: notes,
      dueDate: dueDate,
      excludeFromCalculations: excludeFromCalculations,
      accountingMonth: accountingMonth,
    );
  }

  /// Converts an existing plain expense into a split expense — Task 1's
  /// "convert an old expense" flow. Reuses exactly the split-branch logic
  /// [createExpense] runs for a brand-new expense (`resolveShares`,
  /// schedule/installment generation, per-participant `LedgerEntry`s)
  /// against an already-recorded [transactionId] — no second `Transaction`
  /// is ever created, since the account-balance effect of this spend
  /// already happened when it was first recorded.
  ///
  /// [existingExpense] is non-null only when an `Expense` document already
  /// exists for this transaction (theoretically always [SplitType.none] and
  /// unsplit, since a split/assigned expense can't be converted again — see
  /// the guard below); it is updated in place. When null (the common case:
  /// a plain expense added via the ordinary transaction form has no
  /// `Expense` document at all), a brand-new `Expense` document is created
  /// with a fresh id, carrying over [description]/[totalAmount]/[date]/
  /// [categoryId]/[accountId]/[notes] from the transaction and pointing at
  /// its existing [transactionId].
  Future<Expense> convertToSplit({
    Expense? existingExpense,
    required String transactionId,
    required String description,
    required double totalAmount,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required String notes,
    required SplitType splitType,
    required List<ExpenseParticipantInput> participantInputs,
    DateTime? dueDate,
  }) async {
    if (existingExpense != null && existingExpense.isSplit) {
      throw const AppException('This expense has already been shared');
    }

    var participants = resolveShares(type: splitType, total: totalAmount, inputs: participantInputs);
    if (participants.isEmpty) {
      throw const AppException('Choose at least one person to share with');
    }

    final expenseId = existingExpense?.id ?? IdGenerator.generate();

    final result = await _generateScheduleAndLedger(
      expenseId: expenseId,
      participants: participants,
      totalAmount: totalAmount,
      date: date,
      description: description,
      transactionId: transactionId,
      dueDate: dueDate,
    );
    final scheduleId = result.$1;
    participants = result.$2;

    if (existingExpense != null) {
      existingExpense.recordEdit(
        field: 'splitType',
        oldValue: existingExpense.splitType.name,
        newValue: splitType.name,
      );
      existingExpense.splitType = splitType;
      existingExpense.participants = participants;
      existingExpense.scheduleId = scheduleId;
      await update(existingExpense);
      return existingExpense;
    }

    final expense = Expense(
      id: expenseId,
      description: description,
      totalAmount: totalAmount,
      date: date,
      categoryId: categoryId,
      accountId: accountId,
      transactionId: transactionId,
      splitType: splitType,
      participants: participants,
      scheduleId: scheduleId,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await add(expense.id, expense);
    return expense;
  }

  /// Part 1's "assign an existing transaction to a person" — the degenerate
  /// single-participant case of [convertToSplit] (mirrors how
  /// [assignToPerson] wraps [createExpense] for brand-new expenses), so an
  /// already-recorded plain transaction can be retroactively assigned
  /// without a second `Transaction` ever being created. [partialAmount],
  /// when supplied, is the person's share; the rest is implicitly the
  /// payer's own ("Me") share via the same custom-split validation
  /// [resolveShares] already enforces. Omitting it assigns the full amount
  /// to [personId], same as [assignToPerson]'s "full amount" case.
  Future<Expense> convertToAssigned({
    Expense? existingExpense,
    required String transactionId,
    required String description,
    required double totalAmount,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required String notes,
    required String personId,
    required String personName,
    double? partialAmount,
    DateTime? dueDate,
  }) {
    final personShare = partialAmount ?? totalAmount;
    final meShare = _round2(totalAmount - personShare);
    return convertToSplit(
      existingExpense: existingExpense,
      transactionId: transactionId,
      description: description,
      totalAmount: totalAmount,
      date: date,
      categoryId: categoryId,
      accountId: accountId,
      notes: notes,
      splitType: SplitType.custom,
      participantInputs: [
        ExpenseParticipantInput(name: 'Me', isMe: true, value: meShare),
        ExpenseParticipantInput(personId: personId, name: personName, value: personShare),
      ],
      dueDate: dueDate,
    );
  }

  /// Re-splits an already split/assigned expense across a new participant
  /// set — the People flow's "Split Expense" action (Figma frame 5), which
  /// turns a single-person assignment into a multi-way split (or reshuffles
  /// who shares an existing split). Because this discards the old
  /// schedule/installments/ledger entries and regenerates them from scratch,
  /// it is only safe *before any money has been collected* — it throws if any
  /// current installment already has a payment, rather than trying to
  /// reconcile collected amounts against a brand-new participant set.
  /// [editExpense] remains the path for adjusting an existing set's
  /// amounts/shares (which does preserve payments).
  Future<Expense> resplitExpense({
    required Expense expense,
    required SplitType splitType,
    required List<ExpenseParticipantInput> participantInputs,
    DateTime? dueDate,
  }) async {
    final newParticipants = resolveShares(type: splitType, total: expense.totalAmount, inputs: participantInputs);
    if (newParticipants.where((p) => !p.isMe).isEmpty) {
      throw const AppException('Choose at least one person to share with');
    }

    final oldScheduleId = expense.scheduleId;
    if (oldScheduleId != null) {
      final installmentRepository = _installmentRepositoryFor(oldScheduleId);
      final oldInstallments = await installmentRepository.getAll();
      if (oldInstallments.any((i) => i.amountPaid > 0)) {
        throw const AppException(
          'This expense already has payments recorded — remove them before re-splitting.',
        );
      }
      for (final installment in oldInstallments) {
        await installmentRepository.softDelete(installment);
      }
      final schedule = await paymentScheduleRepository.getByKey(oldScheduleId);
      if (schedule != null) await paymentScheduleRepository.softDelete(schedule);
    }

    // Reverse + soft-delete the original per-person "gave" entries so their
    // pending balances don't double-count once the new ones are posted.
    for (final participant in expense.participants) {
      if (participant.personId == null) continue;
      final person = await personRepository.getByKey(participant.personId!);
      if (person == null) continue;
      final ledgerRepository = _ledgerRepositoryFor(person.id);
      final linked = (await ledgerRepository.getByTransactionRef(expense.transactionId))
          .where((e) => e.type == LedgerEntryType.gave);
      for (final entry in linked) {
        await ledgerRepository.softDeleteEntry(person, entry);
      }
    }

    final result = await _generateScheduleAndLedger(
      expenseId: expense.id,
      participants: newParticipants,
      totalAmount: expense.totalAmount,
      date: expense.date,
      description: expense.description,
      transactionId: expense.transactionId,
      dueDate: dueDate,
    );

    expense.recordEdit(field: 'splitType', oldValue: expense.splitType.name, newValue: splitType.name);
    expense.splitType = splitType;
    expense.participants = result.$2;
    expense.scheduleId = result.$1;
    await update(expense);
    return expense;
  }

  /// Edits an existing expense in place — simple fields (description, date,
  /// category, account, notes) always apply; [totalAmount]/[splitType]/
  /// [participantInputs] only matter when [expense] is split, and re-resolve
  /// every participant's share via [resolveShares], same engine
  /// [createExpense] uses. [currentInstallments] must be the caller's
  /// already-loaded installments for [expense.scheduleId] (the UI already
  /// streams these via `installmentsStreamProvider` to render participant
  /// status, so no extra read is needed here).
  ///
  /// Never lets a participant's new share drop below what they've already
  /// paid — throws rather than silently clamping/refunding, since this is a
  /// personal ledger and a silent balance change would be worse than
  /// blocking the edit. This also means participants can't be removed
  /// entirely once they've paid anything; adding/removing participants is
  /// out of scope for this method (only the existing set's amounts/details
  /// change) — use [convertToSplit]/[convertToAssigned] for that.
  ///
  /// Always keeps the linked [Transaction] in sync via
  /// [TransactionRepository.editTransaction] so `Transaction.amount` can
  /// never desync from `Expense.totalAmount` — this was the root cause of
  /// split expenses silently corrupting when edited through the plain
  /// transaction form.
  Future<Expense> editExpense({
    required Expense expense,
    required List<Installment> currentInstallments,
    String? description,
    double? totalAmount,
    DateTime? date,
    String? categoryId,
    String? accountId,
    String? notes,
    SplitType? splitType,
    List<ExpenseParticipantInput>? participantInputs,
    DateTime? dueDate,
  }) async {
    expense.updateField(
      field: 'description',
      oldValue: expense.description,
      newValue: description,
      apply: (v) => expense.description = v,
    );
    expense.updateField(
      field: 'date',
      oldValue: expense.date,
      newValue: date,
      apply: (v) => expense.date = v,
    );
    expense.updateField(
      field: 'categoryId',
      oldValue: expense.categoryId,
      newValue: categoryId,
      apply: (v) => expense.categoryId = v,
    );
    expense.updateField(
      field: 'accountId',
      oldValue: expense.accountId,
      newValue: accountId,
      apply: (v) => expense.accountId = v,
    );
    expense.updateField(
      field: 'notes',
      oldValue: expense.notes,
      newValue: notes,
      apply: (v) => expense.notes = v,
    );

    final resplitting = expense.isSplit &&
        (totalAmount != null || splitType != null || participantInputs != null);
    double? syncedTransactionAmount = totalAmount;

    if (resplitting) {
      if (participantInputs == null) {
        throw const AppException('Choose who to share this expense with');
      }
      final newTotal = totalAmount ?? expense.totalAmount;
      final newSplitType = splitType ?? expense.splitType;
      final installmentById = {for (final i in currentInstallments) i.id: i};

      final newParticipants = resolveShares(type: newSplitType, total: newTotal, inputs: participantInputs);
      if (newParticipants.isEmpty) {
        throw const AppException('Choose at least one person to share with');
      }

      final oldByKey = {for (final p in expense.participants) _participantKey(p): p};

      for (final participant in newParticipants) {
        if (participant.isMe) continue;
        final old = oldByKey[_participantKey(participant)];
        final installment = old?.installmentId == null ? null : installmentById[old!.installmentId];
        if (installment == null) continue;
        if (participant.share < installment.amountPaid) {
          throw AppException(
            '${participant.name} has already been paid ${installment.amountPaid.toStringAsFixed(2)} — '
            "their share can't be reduced below that",
          );
        }
      }

      final scheduleId = expense.scheduleId;
      if (scheduleId == null) {
        throw const AppException('This expense has no tracking schedule to update');
      }
      final installmentRepository = _installmentRepositoryFor(scheduleId);

      final resolvedParticipants = <ExpenseParticipant>[];
      for (final participant in newParticipants) {
        if (participant.isMe) {
          resolvedParticipants.add(participant);
          continue;
        }
        final old = oldByKey[_participantKey(participant)];
        final installment = old?.installmentId == null ? null : installmentById[old!.installmentId];
        if (installment == null) {
          resolvedParticipants.add(participant);
          continue;
        }

        await installmentRepository.editInstallmentAmount(installment, participant.share);

        final delta = _round2(participant.share - (old?.share ?? 0));
        if (delta != 0 && participant.personId != null) {
          final person = await personRepository.getByKey(participant.personId!);
          if (person != null) {
            final ledgerRepository = _ledgerRepositoryFor(person.id);
            final entries = await ledgerRepository.getByTransactionRef(expense.transactionId);
            final LedgerEntry? originalEntry = entries.where((e) => e.type == LedgerEntryType.gave).firstOrNull;
            if (originalEntry != null) {
              // Corrects the same "Split: ..."/"gave" entry the person's
              // statement already shows, so its displayed amount moves in
              // step with the just-synced Transaction/Installment instead
              // of staying stale next to a separate "Correct Balance" line.
              await ledgerRepository.editEntryAmount(person, originalEntry, participant.share);
            } else {
              // The original entry is gone (e.g. manually deleted from the
              // person's timeline) — fall back to a standalone correction
              // so the balance still stays in sync.
              await ledgerRepository.addEntry(
                person,
                type: LedgerEntryType.adjustment,
                amount: delta.abs(),
                date: date ?? expense.date,
                note: 'Edited: ${description ?? expense.description}',
                increasesBalance: delta >= 0,
              );
            }
          }
        }

        resolvedParticipants.add(participant.copyWith(installmentId: installment.id));
      }

      expense.recordEdit(field: 'totalAmount', oldValue: expense.totalAmount.toString(), newValue: newTotal.toString());
      expense.totalAmount = newTotal;
      expense.recordEdit(field: 'splitType', oldValue: expense.splitType.name, newValue: newSplitType.name);
      expense.splitType = newSplitType;
      expense.participants = resolvedParticipants;
      syncedTransactionAmount = newTotal;
    } else {
      expense.updateField(
        field: 'totalAmount',
        oldValue: expense.totalAmount,
        newValue: totalAmount,
        apply: (v) => expense.totalAmount = v,
      );
    }

    final transaction = await transactionRepository.getByKey(expense.transactionId);
    if (transaction != null) {
      await transactionRepository.editTransaction(
        transaction,
        amount: syncedTransactionAmount,
        dateTime: date,
        accountId: accountId,
        categoryId: categoryId,
        notes: notes,
      );
    }

    if (dueDate != null && expense.scheduleId != null) {
      final installmentRepository = _installmentRepositoryFor(expense.scheduleId!);
      for (final installment in currentInstallments) {
        await installmentRepository.editInstallmentDueDate(installment, dueDate);
      }
    }

    await update(expense);
    return expense;
  }

  /// Matches a participant across an edit — by [personId] when tracked as a
  /// [Person], otherwise by [name] (the same identity a free-text
  /// participant has always had, since they have no other stable key).
  static String _participantKey(ExpenseParticipant p) => p.personId ?? 'name:${p.name}';

  /// Marks one [participant] as settled: records an `InstallmentPayment`
  /// against their tracking installment (via [installmentPaymentRepository],
  /// scoped by the caller to that installment's schedule) and posts a
  /// reversing `LedgerEntry` so their pending balance drops by the settled
  /// amount — the inverse of the `LedgerEntryType.gave` entry [createExpense]
  /// posted for them.
  Future<void> settleParticipant({
    required Expense expense,
    required ExpenseParticipant participant,
    required Installment installment,
    required InstallmentPaymentRepository installmentPaymentRepository,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (participant.installmentId != installment.id) {
      throw const AppException('This payment does not belong to this person');
    }

    await installmentPaymentRepository.recordPayment(installment, amount: amount, date: date, note: note);

    if (participant.personId == null) return;
    final person = await personRepository.getByKey(participant.personId!);
    if (person == null) return;
    await _ledgerRepositoryFor(person.id).addEntry(
      person,
      type: LedgerEntryType.receivedBack,
      amount: amount,
      date: date,
      note: 'Split settlement: ${expense.description}',
      transactionRef: expense.transactionId,
    );
  }

  /// Reverses this expense's ledger/schedule effect without touching the
  /// underlying [Transaction] — the symmetric counterpart to
  /// [assignToPerson]/[convertToAssigned] for "this person no longer owes me
  /// this expense" (toggling the Add Expense screen's owed switch off, or
  /// removing/changing the linked person). Shares [deleteExpense]'s
  /// schedule/installment/ledger cleanup exactly (same
  /// `transactionRef == expense.transactionId` lookup, same
  /// [LedgerRepository.softDeleteEntry] reversal), but deliberately does NOT
  /// soft-delete the [Transaction] or the [Expense] document itself — the
  /// caller (`AddExpenseScreen`) still owns a live transaction it wants to
  /// keep (as a plain expense, or to reassign to someone else immediately
  /// after). Leaves [expense] soft-deleted so no dangling `SplitType.custom`/
  /// participant state is left behind for a transaction that is no longer
  /// "owed" — callers that want to keep tracking it as a plain reference
  /// should not call this a second time for the same expense.
  Future<void> unassignFromPerson(Expense expense) async {
    final scheduleId = expense.scheduleId;
    if (scheduleId != null) {
      final installmentRepository = _installmentRepositoryFor(scheduleId);
      for (final installment in await installmentRepository.getAll()) {
        await installmentRepository.softDelete(installment);
      }
      final schedule = await paymentScheduleRepository.getByKey(scheduleId);
      if (schedule != null) {
        await paymentScheduleRepository.softDelete(schedule);
      }
    }

    for (final participant in expense.participants) {
      if (participant.personId == null) continue;
      final person = await personRepository.getByKey(participant.personId!);
      if (person == null) continue;
      final ledgerRepository = _ledgerRepositoryFor(person.id);
      final linkedEntries = await ledgerRepository.getByTransactionRef(expense.transactionId);
      for (final entry in linkedEntries) {
        await ledgerRepository.softDeleteEntry(person, entry);
      }
    }

    await softDelete(expense);
  }

  /// Cascading soft-delete for a split/assigned expense — the Figma "Delete
  /// Expense" action. Mirrors [TransactionRepository.softDeleteTransaction]
  /// for the account balance, then soft-deletes the [Expense] itself, its
  /// `PaymentSchedule` and every `Installment`, and reverses + soft-deletes
  /// every person [LedgerEntry] this expense posted (the original "gave"
  /// entry and any "receivedBack" settlements it collected) via
  /// [LedgerRepository.softDeleteEntry], so nothing keeps counting toward
  /// an account's or a person's balance once this expense is gone.
  ///
  /// See [restoreExpense] for the matching cascade back out of trash.
  Future<void> deleteExpense(Expense expense) async {
    final transaction = await transactionRepository.getByKey(expense.transactionId);
    if (transaction != null) {
      await transactionRepository.softDeleteTransaction(transaction);
    }

    final scheduleId = expense.scheduleId;
    if (scheduleId != null) {
      final installmentRepository = _installmentRepositoryFor(scheduleId);
      for (final installment in await installmentRepository.getAll()) {
        await installmentRepository.softDelete(installment);
      }
      final schedule = await paymentScheduleRepository.getByKey(scheduleId);
      if (schedule != null) {
        await paymentScheduleRepository.softDelete(schedule);
      }
    }

    for (final participant in expense.participants) {
      if (participant.personId == null) continue;
      final person = await personRepository.getByKey(participant.personId!);
      if (person == null) continue;
      final ledgerRepository = _ledgerRepositoryFor(person.id);
      final linkedEntries = await ledgerRepository.getByTransactionRef(expense.transactionId);
      for (final entry in linkedEntries) {
        await ledgerRepository.softDeleteEntry(person, entry);
      }
    }

    await softDelete(expense);
  }

  /// Restores everything [deleteExpense] cascaded — the exact inverse, so a
  /// trashed "owed" expense comes back as an owed expense again instead of
  /// reverting to a plain transaction. Re-applies the [Transaction]'s
  /// account-balance effect, restores its `PaymentSchedule` and every
  /// `Installment`, restores every person [LedgerEntry] this expense posted
  /// (re-applying each one's balance effect), then restores the [Expense]
  /// itself. Only restores a piece that is still actually in trash — each
  /// `isDeleted`/[getTrash] check guards against double-applying a balance
  /// effect if that piece was already independently restored first (e.g. via
  /// a granular trash screen, or a second call for the same expense).
  Future<void> restoreExpense(Expense expense) async {
    final transaction = await transactionRepository.getByKey(expense.transactionId);
    if (transaction != null && transaction.isDeleted) {
      await transactionRepository.restoreTransaction(transaction);
    }

    final scheduleId = expense.scheduleId;
    if (scheduleId != null) {
      final installmentRepository = _installmentRepositoryFor(scheduleId);
      for (final installment in await installmentRepository.getTrash()) {
        await installmentRepository.restore(installment);
      }
      final schedule = await paymentScheduleRepository.getByKey(scheduleId);
      if (schedule != null && schedule.isDeleted) {
        await paymentScheduleRepository.restore(schedule);
      }
    }

    for (final participant in expense.participants) {
      if (participant.personId == null) continue;
      final person = await personRepository.getByKey(participant.personId!);
      if (person == null) continue;
      final ledgerRepository = _ledgerRepositoryFor(person.id);
      final linkedEntries = await ledgerRepository.getTrashByTransactionRef(expense.transactionId);
      for (final entry in linkedEntries) {
        await ledgerRepository.restoreEntry(person, entry);
      }
    }

    await restore(expense);
  }
}
