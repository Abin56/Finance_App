import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../../../core/constants/firestore_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/interest/interest_calculator.dart';
import '../../../core/interest/interest_period.dart';
import '../../../core/payment_schedule/domain/disbursement_reamortization_policy.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/installment_settlement.dart';
import '../../../core/payment_schedule/domain/payment_allocation_type.dart';
import '../../../core/payment_schedule/domain/payment_schedule.dart';
import '../../../core/payment_schedule/domain/precomputed_installment_amount.dart';
import '../../../core/payment_schedule/domain/prepayment_reamortization_policy.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../core/utils/id_generator.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/domain/transaction.dart' as domain;
import '../../transactions/domain/transaction_type.dart';
import '../domain/loan.dart';
import '../domain/loan_additional_disbursement.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_reamortization_event.dart';
import '../domain/loan_repayment_type.dart';

/// Outcome of [LoanAdvancePaymentRepository.record].
class LoanAdvancePaymentResult {
  const LoanAdvancePaymentResult({
    required this.alreadyRecorded,
    required this.paymentIds,
    required this.installmentIds,
    required this.transactionId,
    required this.overallAllocationType,
    required this.prepaymentPrincipalAmount,
    required this.overflowPaymentId,
    required this.overflowInstallmentId,
    required this.reamortization,
  });

  /// True when [idempotencyKey] had already been used — every other field
  /// still describes the original (not re-applied) result, so a caller
  /// retrying after a network timeout gets back the real outcome rather
  /// than an error.
  final bool alreadyRecorded;

  /// The regular fan-out payment ids, in the same order as [installmentIds]
  /// (`paymentIds[i]` was applied to `installmentIds[i]`) — does NOT include
  /// [overflowPaymentId]. Required, alongside [transactionId], to later call
  /// [LoanAdvancePaymentRepository.reversePayment] for this action.
  final List<String> paymentIds;

  /// The installment ids [paymentIds] were applied to, parallel to
  /// [paymentIds].
  final List<String> installmentIds;

  final String transactionId;
  final PaymentAllocationType overallAllocationType;

  /// Null unless [overallAllocationType] is
  /// [PaymentAllocationType.principalPrepayment].
  final double? prepaymentPrincipalAmount;

  /// The ledger-only overflow payment's id, when this action produced one —
  /// null otherwise. Required to reverse a principal-prepayment action.
  final String? overflowPaymentId;

  /// Which installment [overflowPaymentId] is attached to (always the
  /// schedule's last installment — see [record]'s doc comment).
  final String? overflowInstallmentId;

  /// Null when this payment did not trigger a prepayment (no re-amortization
  /// attempted). Present — [PrepaymentReamortizationSolved] or
  /// [PrepaymentReamortizationUnsolvable] — whenever it did.
  final PrepaymentReamortizationOutcome? reamortization;
}

/// Outcome of [LoanAdvancePaymentRepository.reversePayment].
class PaymentReversalResult {
  const PaymentReversalResult({
    required this.alreadyReversed,
    required this.scheduleRestored,
    this.scheduleRestorationSkippedReason,
  });

  /// True when this exact transaction was already reversed (its
  /// `Transaction` document was already soft-deleted) — every other field
  /// still describes the (unchanged) current state, so a retried reversal
  /// request is a safe no-op rather than an error.
  final bool alreadyReversed;

  /// True when the reversed payment had triggered a re-amortization and
  /// that schedule reshape was successfully undone (original tail
  /// restored, regenerated tail retired). Always false for a
  /// regular/advance payment reversal (nothing to restore).
  final bool scheduleRestored;

  /// Set only when this reversal was for a principal prepayment AND the
  /// money was successfully reversed but the schedule restoration batch
  /// was skipped — e.g. a concurrent payment landed on the regenerated
  /// tail between the eligibility check and the restoration batch. The
  /// payment itself is still correctly reversed; the schedule needs a
  /// manual "Edit Loan Terms" correction. Null whenever [scheduleRestored]
  /// is true or no schedule restoration was needed.
  final String? scheduleRestorationSkippedReason;
}

/// Outcome of [LoanAdvancePaymentRepository.recordAdditionalDisbursement].
class LoanAdditionalDisbursementResult {
  const LoanAdditionalDisbursementResult({
    required this.alreadyRecorded,
    required this.disbursementId,
    required this.transactionId,
    required this.reamortization,
  });

  /// True when [LoanAdvancePaymentRepository.recordAdditionalDisbursement]'s
  /// `idempotencyKey` had already been used — every other field still
  /// describes the original (not re-applied) result.
  final bool alreadyRecorded;

  /// Id of the `LoanAdditionalDisbursement` audit doc this action wrote —
  /// required, alongside [transactionId], to later call
  /// [LoanAdvancePaymentRepository.reversePayment] for this action.
  final String disbursementId;

  final String transactionId;

  /// Null when the disbursement did not trigger a re-amortization (no
  /// remaining unsettled installments to reshape). Present — either
  /// [DisbursementReamortizationSolved] or
  /// [DisbursementReamortizationUnsolvable] — whenever it did.
  final DisbursementReamortizationOutcome? reamortization;
}

/// Atomic, idempotent recording of an advance/regular/prepayment against a
/// Loan's installment schedule — the safety-critical write path for the new
/// Advance/Prepayment feature. Deliberately does **not** call
/// `TransactionRepository.createTransaction`/`InstallmentPaymentRepository.
/// recordPayment` (both are plain sequential, non-transactional writes
/// today — see `docs/global-financial-integrity-audit.md` finding F1): this
/// class performs the equivalent writes itself, inside one
/// `runTransaction`, so this new feature never depends on or reintroduces
/// that gap. The existing regular-EMI-payment flow is untouched and keeps
/// its current (non-atomic, no Account/Transaction linkage) behavior.
///
/// Two-unit write shape, matching `docs`'s atomicity conventions:
///  1. Fixed-size core — payment doc(s), `Installment.amountPaid`,
///     `Transaction`, `Account.currentBalance` — one `runTransaction`,
///     re-reading every document fresh (never trusting the caller's
///     possibly-stale in-memory copies), so concurrent payments on the same
///     loan/account serialize correctly instead of losing an update.
///  2. Variable-length re-amortization tail (only when the payment
///     overflows into a principal prepayment) — one `writeBatch`, run only
///     after unit 1 commits. If it fails, the payment stays correctly
///     recorded; only the automatic schedule reshape is skipped, surfaced
///     to the caller as [PrepaymentReamortizationUnsolvable] so the UI can
///     offer the manual "Edit Loan Terms" fallback. Full end-to-end
///     atomicity across both units is not attempted — same best-effort
///     posture the codebase already uses for `createTransferPair` (web).
///
/// Classification scope: a payment is checked against the installments
/// **currently due** (overdue, or — if none are overdue — the single next
/// upcoming one), unless [includeUpcomingInstallments] is set (the "Apply
/// to upcoming EMIs" allocation choice), which checks it against every
/// remaining installment instead. Whatever remains unallocated after that
/// becomes a principal prepayment — this scope decision is what the sheet's
/// UI drives via [includeUpcomingInstallments]; this repository never
/// guesses it on its own.
class LoanAdvancePaymentRepository {
  LoanAdvancePaymentRepository({
    required FirebaseFirestore firestore,
    required String uid,
    this.policy = const ReduceTenurePolicy(),
    this.disbursementPolicy = const HoldTenurePolicy(),
  }) : _firestore = firestore,
       _uid = uid;

  final FirebaseFirestore _firestore;
  final String _uid;
  final PrepaymentReamortizationPolicy policy;
  final DisbursementReamortizationPolicy disbursementPolicy;

  DocumentReference<Account> _accountRef(String accountId) => _firestore
      .collection(FirestoreCollections.users)
      .doc(_uid)
      .collection(FirestoreCollections.accounts)
      .withConverter<Account>(
        fromFirestore: Account.fromFirestore,
        toFirestore: (a, _) => a.toFirestore(),
      )
      .doc(accountId);

  DocumentReference<domain.Transaction> _transactionRef(String id) =>
      _firestore
          .collection(FirestoreCollections.users)
          .doc(_uid)
          .collection(FirestoreCollections.transactions)
          .withConverter<domain.Transaction>(
            fromFirestore: domain.Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          )
          .doc(id);

  DocumentReference<Loan> _loanRef(String loanId) => _firestore
      .collection(FirestoreCollections.users)
      .doc(_uid)
      .collection(FirestoreCollections.loans)
      .withConverter<Loan>(
        fromFirestore: Loan.fromFirestore,
        toFirestore: (l, _) => l.toFirestore(),
      )
      .doc(loanId);

  DocumentReference<PaymentSchedule> _scheduleRef(String scheduleId) =>
      _firestore
          .collection(FirestoreCollections.users)
          .doc(_uid)
          .collection(FirestoreCollections.paymentSchedules)
          .withConverter<PaymentSchedule>(
            fromFirestore: PaymentSchedule.fromFirestore,
            toFirestore: (s, _) => s.toFirestore(),
          )
          .doc(scheduleId);

  CollectionReference<Installment> _installments(String scheduleId) =>
      _scheduleRef(
        scheduleId,
      ).collection(FirestoreCollections.installments).withConverter<Installment>(
        fromFirestore: Installment.fromFirestore,
        toFirestore: (i, _) => i.toFirestore(),
      );

  CollectionReference<InstallmentPayment> _payments(
    String scheduleId,
    String installmentId,
  ) => _installments(scheduleId)
      .doc(installmentId)
      .collection(FirestoreCollections.payments)
      .withConverter<InstallmentPayment>(
        fromFirestore: InstallmentPayment.fromFirestore,
        toFirestore: (p, _) => p.toFirestore(),
      );

  DocumentReference<InstallmentPayment> _paymentRef(
    String scheduleId,
    String installmentId,
    String paymentId,
  ) => _payments(scheduleId, installmentId).doc(paymentId);

  CollectionReference<LoanReamortizationEvent> _reamortizationEvents(
    String loanId,
  ) => _loanRef(loanId)
      .collection(FirestoreCollections.reamortizationEvents)
      .withConverter<LoanReamortizationEvent>(
        fromFirestore: LoanReamortizationEvent.fromFirestore,
        toFirestore: (e, _) => e.toFirestore(),
      );

  CollectionReference<LoanAdditionalDisbursement> _disbursements(
    String loanId,
  ) => _loanRef(loanId)
      .collection(FirestoreCollections.additionalDisbursements)
      .withConverter<LoanAdditionalDisbursement>(
        fromFirestore: LoanAdditionalDisbursement.fromFirestore,
        toFirestore: (d, _) => d.toFirestore(),
      );

  /// Records a payment toward [loan] and returns its classification +
  /// (when applicable) re-amortization outcome. [scheduleInstallments] must
  /// be every active (non-deleted) installment on `loan.scheduleId` — only
  /// its installment **ids** are trusted (ids/due dates are immutable once
  /// generated); every installment's `amountPaid`/`remainingAmount` is
  /// re-read fresh inside the transaction and classification/allocation is
  /// computed from that fresh state, never from whatever the caller happens
  /// to be holding — this is what keeps a concurrent second payment on the
  /// same loan from allocating against a stale "still owed" snapshot.
  /// [idempotencyKey] must be generated once per user action (e.g. when the
  /// payment sheet opens) and reused verbatim on any retry of that same
  /// action — a retry with the same key is detected (via the deterministic
  /// `Transaction` document id it produces) and returns the original result
  /// without re-applying any financial effect, regardless of how much the
  /// schedule has changed between the original call and the retry.
  Future<LoanAdvancePaymentResult> record({
    required Loan loan,
    required List<Installment> scheduleInstallments,
    required String accountId,
    required double amount,
    required DateTime date,
    required String idempotencyKey,
    String note = '',
    bool includeUpcomingInstallments = false,
  }) async {
    if (amount <= 0) {
      throw const AppException('Payment amount must be greater than 0');
    }
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException(
        'One-time loans have a single due amount — pay it directly, there '
        'is no advance/prepayment concept for them',
      );
    }

    // Ids/sequence/dueDate are immutable once an installment is generated —
    // safe to use from the caller's (possibly stale) list purely to know
    // WHICH documents to read fresh. Nothing amount-related is trusted from
    // here.
    final knownIds = [...scheduleInstallments]
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    if (knownIds.isEmpty) {
      throw const AppException('This loan has no installment schedule');
    }
    final lastKnownInstallmentId = knownIds.last.id;
    final transactionId = 'adv_${idempotencyKey}_txn';
    final overflowPaymentId = 'adv_${idempotencyKey}_principal';
    final isIncome = loan.direction == LoanDirection.given;

    final coreResult = await _firestore.runTransaction<_CoreResult>((tx) async {
      // --- All reads first (Firestore transaction constraint). ---
      final sentinelSnap = await tx.get(_transactionRef(transactionId));
      if (sentinelSnap.exists) {
        final existing = sentinelSnap.data()!;
        final overflowSnap = await tx.get(
          _paymentRef(loan.scheduleId, lastKnownInstallmentId, overflowPaymentId),
        );
        final existingOverflow = overflowSnap.data();
        return _CoreResult(
          alreadyRecorded: true,
          paymentIds: [
            if (existing.installmentPaymentId != null)
              existing.installmentPaymentId!,
          ],
          installmentIds: [
            if (existing.installmentId != null) existing.installmentId!,
          ],
          overflowPaymentId: existingOverflow != null ? overflowPaymentId : null,
          overflowInstallmentId:
              existingOverflow != null ? lastKnownInstallmentId : null,
          overallType:
              existing.paymentAllocationType ?? PaymentAllocationType.regularEmi,
          prepaymentPrincipalAmount: existingOverflow?.prepaymentPrincipalAmount,
        );
      }

      final accountSnap = await tx.get(_accountRef(accountId));
      final account = accountSnap.data();
      if (account == null) throw const AppException('Account not found');

      final freshById = <String, Installment>{};
      for (final known in knownIds) {
        final snap = await tx.get(_installments(loan.scheduleId).doc(known.id));
        final fresh = snap.data();
        if (fresh != null) freshById[known.id] = fresh;
      }

      // --- Classification/allocation, computed from FRESH state only. ---
      final freshSorted = knownIds
          .map((k) => freshById[k.id])
          .whereType<Installment>()
          .toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      final eligible = freshSorted
          .where((i) => i.remainingAmount > 0 && !i.isSkipped)
          .toList();
      if (eligible.isEmpty) {
        throw const AppException('This loan is already fully paid');
      }
      final dueNow = eligible.where((i) => !i.dueDate.isAfter(date)).toList();
      final classificationScope = includeUpcomingInstallments
          ? eligible
          : (dueNow.isNotEmpty ? dueNow : [eligible.first]);
      final plan = InstallmentSettlement.plan(classificationScope, amount);
      final overflow = plan.unallocated;

      final paymentIds = [
        for (var i = 0; i < plan.portions.length; i++)
          'adv_${idempotencyKey}_p$i',
      ];
      final installmentIds = [
        for (final portion in plan.portions) portion.installment.id,
      ];
      final overallType = overflow > 0
          ? PaymentAllocationType.principalPrepayment
          : (plan.portions.first.installment.dueDate.isAfter(date)
                ? PaymentAllocationType.advanceEmi
                : PaymentAllocationType.regularEmi);

      // --- Then all writes. ---
      for (var i = 0; i < plan.portions.length; i++) {
        final portion = plan.portions[i];
        final fresh = freshById[portion.installment.id]!;
        final newAmountPaid = (fresh.amountPaid + portion.portion)
            .clamp(0, fresh.amountDue)
            .toDouble();
        fresh.recordEdit(
          field: 'amountPaid',
          oldValue: fresh.amountPaid.toString(),
          newValue: newAmountPaid.toString(),
        );
        fresh.amountPaid = newAmountPaid;
        tx.set(_installments(loan.scheduleId).doc(fresh.id), fresh);

        final allocationType = fresh.dueDate.isAfter(date)
            ? PaymentAllocationType.advanceEmi
            : PaymentAllocationType.regularEmi;
        final payment = InstallmentPayment(
          id: paymentIds[i],
          installmentId: fresh.id,
          scheduleId: loan.scheduleId,
          ownerType: fresh.ownerType,
          ownerId: fresh.ownerId,
          amount: portion.portion,
          date: date,
          note: note,
          createdAt: DateTime.now(),
          remainingBalanceAfterPayment: fresh.remainingAmount,
          allocationType: allocationType,
          transactionId: transactionId,
        );
        tx.set(_paymentRef(loan.scheduleId, fresh.id, payment.id), payment);
      }

      if (overflow > 0) {
        final overflowPayment = InstallmentPayment(
          id: overflowPaymentId,
          installmentId: lastKnownInstallmentId,
          scheduleId: loan.scheduleId,
          ownerType: freshSorted.last.ownerType,
          ownerId: freshSorted.last.ownerId,
          amount: overflow,
          date: date,
          note: note,
          createdAt: DateTime.now(),
          allocationType: PaymentAllocationType.principalPrepayment,
          prepaymentPrincipalAmount: overflow,
          transactionId: transactionId,
        );
        // Ledger-only — deliberately not applied via amountPaid, since this
        // money reduces principal directly, not this (or any) installment's
        // own amountDue.
        tx.set(
          _paymentRef(loan.scheduleId, lastKnownInstallmentId, overflowPayment.id),
          overflowPayment,
        );
      }

      final transactionDoc = domain.Transaction(
        id: transactionId,
        type: isIncome ? TransactionType.income : TransactionType.expense,
        amount: amount,
        dateTime: date,
        accountId: accountId,
        // TODO(Phase 1): point at the real seeded "Loan Payment"/"EMI
        // Payment" system category once that seeding mechanism exists —
        // this placeholder id is fine for the atomic-write-path pass, but
        // must not ship to a payment-recording UI unresolved.
        categoryId: 'loan_payment',
        description: loan.name?.isNotEmpty == true
            ? 'Loan payment — ${loan.name}'
            : 'Loan payment',
        createdAt: DateTime.now(),
        loanId: loan.id,
        installmentId: plan.portions.first.installment.id,
        installmentPaymentId: paymentIds.first,
        paymentAllocationType: overallType,
      );
      tx.set(_transactionRef(transactionId), transactionDoc);

      final delta = isIncome ? amount : -amount;
      final newBalance = account.currentBalance + delta;
      account.recordEdit(
        field: 'currentBalance',
        oldValue: account.currentBalance.toString(),
        newValue: newBalance.toString(),
      );
      account.currentBalance = newBalance;
      tx.set(_accountRef(accountId), account);

      return _CoreResult(
        alreadyRecorded: false,
        paymentIds: paymentIds,
        installmentIds: installmentIds,
        overflowPaymentId: overflow > 0 ? overflowPaymentId : null,
        overflowInstallmentId: overflow > 0 ? lastKnownInstallmentId : null,
        overallType: overallType,
        prepaymentPrincipalAmount: overflow > 0 ? overflow : null,
      );
    });

    if (coreResult.alreadyRecorded || coreResult.overflowPaymentId == null) {
      return LoanAdvancePaymentResult(
        alreadyRecorded: coreResult.alreadyRecorded,
        paymentIds: coreResult.paymentIds,
        installmentIds: coreResult.installmentIds,
        transactionId: transactionId,
        overallAllocationType: coreResult.overallType,
        prepaymentPrincipalAmount: coreResult.prepaymentPrincipalAmount,
        overflowPaymentId: coreResult.overflowPaymentId,
        overflowInstallmentId: coreResult.overflowInstallmentId,
        reamortization: null,
      );
    }

    final reamortization = await _reamortize(
      loan: loan,
      scheduleInstallments: knownIds,
      triggeringPaymentId: coreResult.overflowPaymentId!,
      triggeringInstallmentId: lastKnownInstallmentId,
      triggeringPrepaymentAmount: coreResult.prepaymentPrincipalAmount!,
      date: date,
    );

    return LoanAdvancePaymentResult(
      alreadyRecorded: false,
      paymentIds: coreResult.paymentIds,
      installmentIds: coreResult.installmentIds,
      transactionId: transactionId,
      overallAllocationType: coreResult.overallType,
      prepaymentPrincipalAmount: coreResult.prepaymentPrincipalAmount,
      overflowPaymentId: coreResult.overflowPaymentId,
      overflowInstallmentId: coreResult.overflowInstallmentId,
      reamortization: reamortization,
    );
  }

  /// Records an increase to [loan]'s principal after origination — e.g. a
  /// second tranche handed over on a loan already in progress. NOT a
  /// payment: money moves in the OPPOSITE direction of [record] — for a
  /// [LoanDirection.given] loan (you lent money), more principal going out
  /// is an expense from [accountId]; for a [LoanDirection.taken] loan (you
  /// borrowed), more principal coming in is income into [accountId]. Only
  /// installment loans are supported — a one-time loan's single due amount
  /// has no "outstanding tail" to re-amortize.
  ///
  /// [scheduleInstallments] must be every active (non-deleted) installment
  /// on `loan.scheduleId`, with the same "only ids/immutable fields are
  /// trusted, everything financial is re-read fresh inside the transaction"
  /// contract as [record]. [idempotencyKey] must be generated once per user
  /// action and reused verbatim on any retry — a retry with the same key is
  /// detected via the deterministic `Transaction` document id it produces
  /// and returns the original result without re-applying any financial
  /// effect.
  ///
  /// Two-unit write shape, identical posture to [record]:
  ///  1. Fixed-size core — `LoanAdditionalDisbursement` doc, `Transaction`,
  ///     `Account.currentBalance`, `Loan.loanAmount` — one `runTransaction`.
  ///  2. Variable-length re-amortization of the untouched tail (via
  ///     [disbursementPolicy]) — one `writeBatch`, run only after unit 1
  ///     commits. If it fails or is unsolvable, the disbursement stays
  ///     correctly recorded; only the automatic schedule reshape is
  ///     skipped, surfaced as [DisbursementReamortizationUnsolvable].
  Future<LoanAdditionalDisbursementResult> recordAdditionalDisbursement({
    required Loan loan,
    required List<Installment> scheduleInstallments,
    required String accountId,
    required double amount,
    required DateTime date,
    required String idempotencyKey,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('Disbursement amount must be greater than 0');
    }
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException(
        'One-time loans have a single due amount — there is no additional '
        'disbursement concept for them',
      );
    }

    final knownIds = [...scheduleInstallments]
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    if (knownIds.isEmpty) {
      throw const AppException('This loan has no installment schedule');
    }
    final transactionId = 'disb_${idempotencyKey}_txn';
    final disbursementId = 'disb_${idempotencyKey}_d';
    // Opposite of `record()`'s `isIncome`: more principal OUT (given) is an
    // expense; more principal IN (taken) is income.
    final isIncome = loan.direction == LoanDirection.taken;

    final coreResult = await _firestore.runTransaction<_DisbursementCoreResult>((
      tx,
    ) async {
      // --- All reads first (Firestore transaction constraint). ---
      final sentinelSnap = await tx.get(_transactionRef(transactionId));
      if (sentinelSnap.exists) {
        final existingDisbSnap = await tx.get(
          _disbursements(loan.id).doc(disbursementId),
        );
        return _DisbursementCoreResult(
          alreadyRecorded: true,
          disbursementId: existingDisbSnap.exists ? disbursementId : '',
        );
      }

      final accountSnap = await tx.get(_accountRef(accountId));
      final account = accountSnap.data();
      if (account == null) throw const AppException('Account not found');

      final freshLoanSnap = await tx.get(_loanRef(loan.id));
      final freshLoan = freshLoanSnap.data();
      if (freshLoan == null) {
        throw const NotFoundException('Loan not found');
      }

      // --- Then all writes. ---
      final disbursement = LoanAdditionalDisbursement(
        id: disbursementId,
        loanId: loan.id,
        amount: amount,
        date: date,
        note: note,
        createdAt: DateTime.now(),
        transactionId: transactionId,
      );
      tx.set(_disbursements(loan.id).doc(disbursementId), disbursement);

      final transactionDoc = domain.Transaction(
        id: transactionId,
        type: isIncome ? TransactionType.income : TransactionType.expense,
        amount: amount,
        dateTime: date,
        accountId: accountId,
        // TODO(Phase 1): point at the real seeded "Loan Disbursement" system
        // category once that seeding mechanism exists.
        categoryId: 'loan_payment',
        description: loan.name?.isNotEmpty == true
            ? 'Additional disbursement — ${loan.name}'
            : 'Additional disbursement',
        createdAt: DateTime.now(),
        loanId: loan.id,
        paymentAllocationType: PaymentAllocationType.additionalDisbursement,
      );
      tx.set(_transactionRef(transactionId), transactionDoc);

      final delta = isIncome ? amount : -amount;
      final newBalance = account.currentBalance + delta;
      account.recordEdit(
        field: 'currentBalance',
        oldValue: account.currentBalance.toString(),
        newValue: newBalance.toString(),
      );
      account.currentBalance = newBalance;
      tx.set(_accountRef(accountId), account);

      final newLoanAmount = freshLoan.loanAmount + amount;
      freshLoan.recordEdit(
        field: 'loanAmount (additional disbursement)',
        oldValue: freshLoan.loanAmount.toString(),
        newValue: newLoanAmount.toString(),
      );
      freshLoan.loanAmount = newLoanAmount;
      tx.set(_loanRef(loan.id), freshLoan);

      return _DisbursementCoreResult(
        alreadyRecorded: false,
        disbursementId: disbursementId,
      );
    });

    if (coreResult.alreadyRecorded) {
      return LoanAdditionalDisbursementResult(
        alreadyRecorded: true,
        disbursementId: coreResult.disbursementId,
        transactionId: transactionId,
        reamortization: null,
      );
    }

    final reamortization = await _reamortizeForDisbursement(
      loan: loan,
      triggeringDisbursementId: disbursementId,
      disbursementAmount: amount,
      date: date,
    );

    return LoanAdditionalDisbursementResult(
      alreadyRecorded: false,
      disbursementId: disbursementId,
      transactionId: transactionId,
      reamortization: reamortization,
    );
  }

  /// Reverses a payment/prepayment action previously recorded via [record],
  /// restoring the financial state as though it had not occurred. Safe to
  /// retry: once the linked `Transaction` is soft-deleted, a repeated call
  /// with the same [transactionId] is a no-op (`alreadyReversed: true`).
  ///
  /// [paymentIds]/[installmentIds] and [overflowPaymentId]/
  /// [overflowInstallmentId] must be exactly what [record] returned for
  /// this action (`LoanAdvancePaymentResult.paymentIds`/`installmentIds`/
  /// `overflowPaymentId`/`overflowInstallmentId`) — this method does not
  /// discover them independently, mirroring [record]'s own
  /// caller-supplies-known-ids, repository-re-reads-fresh contract.
  ///
  /// Eligibility (checked before any write): this action must be the most
  /// recent financial mutation on the loan — no later active payment on any
  /// of its installments, and (for a prepayment) no later re-amortization
  /// event and no payment yet recorded against the installments it
  /// generated. Reversing anything other than the latest action risks
  /// silently rewriting later financial history, so this throws
  /// [PaymentReversalBlockedException] rather than attempting it.
  Future<PaymentReversalResult> reversePayment({
    required Loan loan,
    required String transactionId,
    required List<String> paymentIds,
    required List<String> installmentIds,
    String? overflowPaymentId,
    String? overflowInstallmentId,
    required String reversalIdempotencyKey,
  }) async {
    if (paymentIds.length != installmentIds.length) {
      throw const AppException(
        'paymentIds and installmentIds must be the same length',
      );
    }

    final transactionSnap = await _transactionRef(transactionId).get();
    final transaction = transactionSnap.data();
    if (transaction == null) {
      throw const NotFoundException('Transaction not found');
    }
    if (transaction.isDeleted) {
      return const PaymentReversalResult(
        alreadyReversed: true,
        scheduleRestored: false,
      );
    }

    LoanReamortizationEvent? event;
    if (overflowPaymentId != null) {
      event = await _findTriggeringEvent(loan.id, overflowPaymentId);
      if (event == null) {
        throw const PaymentReversalBlockedException(
          'No re-amortization event found for this prepayment — cannot '
          'safely reverse without knowing which installments it changed',
        );
      }
      if (event.reversed) {
        return const PaymentReversalResult(
          alreadyReversed: true,
          scheduleRestored: false,
        );
      }
      if (event.retiredInstallmentIds.isEmpty &&
          event.generatedInstallmentIds.isEmpty) {
        throw const PaymentReversalBlockedException(
          'This re-amortization predates schedule-restoration tracking and '
          'cannot be safely reversed automatically — use Edit Loan Terms '
          'to adjust the schedule manually instead',
        );
      }
    }

    await _assertReversible(loan: loan, transaction: transaction, event: event);

    final alreadyReversed = await _firestore.runTransaction<bool>((tx) async {
      // --- All reads first. ---
      final freshTransactionSnap = await tx.get(_transactionRef(transactionId));
      final freshTransaction = freshTransactionSnap.data();
      if (freshTransaction == null) {
        throw const NotFoundException('Transaction not found');
      }
      if (freshTransaction.isDeleted) return true; // idempotent race guard

      final freshAccountSnap = await tx.get(
        _accountRef(freshTransaction.accountId),
      );
      final account = freshAccountSnap.data();
      if (account == null) throw const AppException('Account not found');

      final freshInstallments = <String, Installment>{};
      for (final installmentId in installmentIds.toSet()) {
        final snap = await tx.get(
          _installments(loan.scheduleId).doc(installmentId),
        );
        final fresh = snap.data();
        if (fresh != null) freshInstallments[installmentId] = fresh;
      }

      final freshPayments = <String, InstallmentPayment>{};
      for (var i = 0; i < paymentIds.length; i++) {
        final snap = await tx.get(
          _paymentRef(loan.scheduleId, installmentIds[i], paymentIds[i]),
        );
        final fresh = snap.data();
        if (fresh != null) freshPayments[paymentIds[i]] = fresh;
      }
      InstallmentPayment? freshOverflowPayment;
      if (overflowPaymentId != null && overflowInstallmentId != null) {
        final overflowSnap = await tx.get(
          _paymentRef(loan.scheduleId, overflowInstallmentId, overflowPaymentId),
        );
        freshOverflowPayment = overflowSnap.data();
      }

      // --- Then all writes. ---
      for (var i = 0; i < paymentIds.length; i++) {
        final paymentId = paymentIds[i];
        final installmentId = installmentIds[i];
        final payment = freshPayments[paymentId];
        if (payment == null || payment.isDeleted) continue;

        final fresh = freshInstallments[installmentId];
        if (fresh != null) {
          final newAmountPaid = (fresh.amountPaid - payment.amount)
              .clamp(0, fresh.amountDue)
              .toDouble();
          fresh.recordEdit(
            field: 'amountPaid',
            oldValue: fresh.amountPaid.toString(),
            newValue: newAmountPaid.toString(),
          );
          fresh.amountPaid = newAmountPaid;
          tx.set(_installments(loan.scheduleId).doc(fresh.id), fresh);
        }

        payment.markDeleted();
        tx.set(_paymentRef(loan.scheduleId, installmentId, paymentId), payment);
      }

      if (freshOverflowPayment != null && !freshOverflowPayment.isDeleted) {
        // Ledger-only — never applied to any installment's amountPaid, so
        // nothing to reverse there, only the payment doc itself.
        freshOverflowPayment.markDeleted();
        tx.set(
          _paymentRef(loan.scheduleId, overflowInstallmentId!, overflowPaymentId!),
          freshOverflowPayment,
        );
      }

      // Reverses the account balance and soft-deletes the Transaction —
      // inlined rather than delegating to softDeleteTransactionInTransaction,
      // since that method does its own tx.get(account) internally and
      // Firestore requires every read in a transaction to precede every
      // write; the installment/payment writes above must happen after this
      // method's own reads, which means its read can't be deferred to here.
      final delta = -freshTransaction.balanceEffect;
      final newBalance = account.currentBalance + delta;
      account.recordEdit(
        field: 'currentBalance',
        oldValue: account.currentBalance.toString(),
        newValue: newBalance.toString(),
      );
      account.currentBalance = newBalance;
      tx.set(_accountRef(freshTransaction.accountId), account);
      freshTransaction.markDeleted();
      tx.set(_transactionRef(transactionId), freshTransaction);

      return false;
    });

    if (alreadyReversed) {
      return const PaymentReversalResult(
        alreadyReversed: true,
        scheduleRestored: false,
      );
    }

    if (event == null) {
      return const PaymentReversalResult(
        alreadyReversed: false,
        scheduleRestored: false,
      );
    }

    return _restoreSchedule(
      loan: loan,
      event: event,
      reversalIdempotencyKey: reversalIdempotencyKey,
    );
  }

  /// Reverses an additional-disbursement action previously recorded via
  /// [recordAdditionalDisbursement], restoring the financial AND schedule
  /// state as though it had not occurred. Safe to retry: once the linked
  /// `Transaction` is soft-deleted, a repeated call with the same
  /// [transactionId] is a no-op (`alreadyReversed: true`).
  ///
  /// [disbursementId] must be exactly what [recordAdditionalDisbursement]
  /// returned for this action. Same eligibility rule as [reversePayment]:
  /// this must be the most recent financial mutation on the loan — no later
  /// active payment/advance/prepayment/disbursement on any of its
  /// installments, no later re-amortization event, and no payment yet
  /// recorded against the installments this disbursement's re-amortization
  /// generated. Throws [PaymentReversalBlockedException] rather than
  /// silently reconstructing history when that can't be proven safe.
  Future<PaymentReversalResult> reverseAdditionalDisbursement({
    required Loan loan,
    required String transactionId,
    required String disbursementId,
    required String reversalIdempotencyKey,
  }) async {
    final transactionSnap = await _transactionRef(transactionId).get();
    final transaction = transactionSnap.data();
    if (transaction == null) {
      throw const NotFoundException('Transaction not found');
    }
    if (transaction.isDeleted) {
      return const PaymentReversalResult(
        alreadyReversed: true,
        scheduleRestored: false,
      );
    }

    final event = await _findTriggeringEvent(
      loan.id,
      disbursementId,
      field: 'triggeredByDisbursementId',
    );
    // A disbursement doesn't always trigger a re-amortization (e.g. nothing
    // left to reshape — see `_reamortizeForDisbursement`'s doc comment), so
    // — unlike a prepayment's overflow — a missing event is not itself an
    // error. Only a disbursement's own loanAmount bump needs reversing in
    // that case; [event] simply stays null and the schedule-restoration
    // step below is skipped.
    if (event != null) {
      if (event.reversed) {
        return const PaymentReversalResult(
          alreadyReversed: true,
          scheduleRestored: false,
        );
      }
      if (event.retiredInstallmentIds.isEmpty &&
          event.generatedInstallmentIds.isEmpty) {
        throw const PaymentReversalBlockedException(
          'This re-amortization predates schedule-restoration tracking and '
          'cannot be safely reversed automatically — use Edit Loan Terms '
          'to adjust the schedule manually instead',
        );
      }
      if (event.loanAmountBefore == null) {
        throw const PaymentReversalBlockedException(
          'This disbursement predates reversal tracking and cannot be '
          'safely reversed automatically',
        );
      }
    }

    await _assertReversible(loan: loan, transaction: transaction, event: event);

    final alreadyReversed = await _firestore.runTransaction<bool>((tx) async {
      // --- All reads first. ---
      final freshTransactionSnap = await tx.get(_transactionRef(transactionId));
      final freshTransaction = freshTransactionSnap.data();
      if (freshTransaction == null) {
        throw const NotFoundException('Transaction not found');
      }
      if (freshTransaction.isDeleted) return true; // idempotent race guard

      final freshAccountSnap = await tx.get(
        _accountRef(freshTransaction.accountId),
      );
      final account = freshAccountSnap.data();
      if (account == null) throw const AppException('Account not found');

      final freshDisbursementSnap = await tx.get(
        _disbursements(loan.id).doc(disbursementId),
      );
      final freshDisbursement = freshDisbursementSnap.data();

      final freshLoanSnap = await tx.get(_loanRef(loan.id));
      final freshLoan = freshLoanSnap.data();
      if (freshLoan == null) throw const NotFoundException('Loan not found');

      // --- Then all writes. ---
      if (freshDisbursement != null && !freshDisbursement.isDeleted) {
        freshDisbursement.markDeleted();
        tx.set(
          _disbursements(loan.id).doc(disbursementId),
          freshDisbursement,
        );

        final newLoanAmount = freshLoan.loanAmount - freshDisbursement.amount;
        freshLoan.recordEdit(
          field: 'loanAmount (disbursement reversal)',
          oldValue: freshLoan.loanAmount.toString(),
          newValue: newLoanAmount.toString(),
        );
        freshLoan.loanAmount = newLoanAmount;
        tx.set(_loanRef(loan.id), freshLoan);
      }

      final delta = -freshTransaction.balanceEffect;
      final newBalance = account.currentBalance + delta;
      account.recordEdit(
        field: 'currentBalance',
        oldValue: account.currentBalance.toString(),
        newValue: newBalance.toString(),
      );
      account.currentBalance = newBalance;
      tx.set(_accountRef(freshTransaction.accountId), account);
      freshTransaction.markDeleted();
      tx.set(_transactionRef(transactionId), freshTransaction);

      return false;
    });

    if (alreadyReversed) {
      return const PaymentReversalResult(
        alreadyReversed: true,
        scheduleRestored: false,
      );
    }

    if (event == null) {
      return const PaymentReversalResult(
        alreadyReversed: false,
        scheduleRestored: false,
      );
    }

    return _restoreSchedule(
      loan: loan,
      event: event,
      reversalIdempotencyKey: reversalIdempotencyKey,
    );
  }

  /// Finds the (at most one) non-reversed [LoanReamortizationEvent] whose
  /// [field] (`triggeredByPaymentId` or `triggeredByDisbursementId`) matches
  /// [triggerId].
  Future<LoanReamortizationEvent?> _findTriggeringEvent(
    String loanId,
    String triggerId, {
    String field = 'triggeredByPaymentId',
  }) async {
    final snapshot = await _reamortizationEvents(
      loanId,
    ).where(field, isEqualTo: triggerId).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data();
  }

  /// Read-only eligibility check — throws [PaymentReversalBlockedException]
  /// rather than allowing a reversal that would silently rewrite later
  /// financial history. See [reversePayment]'s doc comment for the rule.
  Future<void> _assertReversible({
    required Loan loan,
    required domain.Transaction transaction,
    required LoanReamortizationEvent? event,
  }) async {
    final allInstallments = await _installments(loan.scheduleId).get();
    for (final doc in allInstallments.docs) {
      final installment = doc.data();
      final paymentsSnap = await _payments(loan.scheduleId, installment.id).get();
      for (final paymentDoc in paymentsSnap.docs) {
        final payment = paymentDoc.data();
        if (payment.isDeleted) continue;
        if (payment.transactionId == transaction.id) continue;
        if (!payment.createdAt.isAfter(transaction.createdAt)) continue;
        throw const PaymentReversalBlockedException(
          'A later payment exists on this loan — reverse it first before '
          'reversing this one',
        );
      }
    }

    if (event == null) return;

    final laterEvents = await _reamortizationEvents(loan.id)
        .where('reversed', isEqualTo: false)
        .get();
    for (final doc in laterEvents.docs) {
      final other = doc.data();
      if (other.id == event.id) continue;
      if (other.createdAt.isAfter(event.createdAt)) {
        throw const PaymentReversalBlockedException(
          'A later re-amortization exists on this loan — reverse it first',
        );
      }
    }

    for (final installmentId in event.generatedInstallmentIds) {
      final snap = await _installments(loan.scheduleId).doc(installmentId).get();
      final installment = snap.data();
      if (installment != null && installment.amountPaid > 0) {
        throw const PaymentReversalBlockedException(
          'A payment already exists against the re-amortized schedule — '
          'reverse it first before reversing this prepayment',
        );
      }
    }
  }

  /// Batch restoration of the schedule a prepayment re-amortized — the
  /// mechanical inverse of [_reamortize]'s batch: restores [event]'s
  /// [LoanReamortizationEvent.retiredInstallmentIds], retires its
  /// [LoanReamortizationEvent.generatedInstallmentIds], reverts
  /// [Loan.installmentCount] and the schedule's cached totals, and marks
  /// the event reversed. Re-validates freshly immediately before
  /// committing — if a concurrent payment landed on the generated tail in
  /// the race window since [_assertReversible] ran, this is skipped
  /// (money stays correctly reversed regardless; only the schedule reshape
  /// is left for a manual "Edit Loan Terms" correction) rather than risking
  /// a mixed/duplicated schedule.
  Future<PaymentReversalResult> _restoreSchedule({
    required Loan loan,
    required LoanReamortizationEvent event,
    required String reversalIdempotencyKey,
  }) async {
    final freshEventSnap = await _reamortizationEvents(
      loan.id,
    ).doc(event.id).get();
    final freshEvent = freshEventSnap.data();
    if (freshEvent == null || freshEvent.reversed) {
      return const PaymentReversalResult(
        alreadyReversed: true,
        scheduleRestored: false,
      );
    }

    for (final installmentId in freshEvent.generatedInstallmentIds) {
      final snap = await _installments(loan.scheduleId).doc(installmentId).get();
      final installment = snap.data();
      if (installment != null && installment.amountPaid > 0) {
        return const PaymentReversalResult(
          alreadyReversed: false,
          scheduleRestored: false,
          scheduleRestorationSkippedReason:
              'A payment landed on the re-amortized schedule after this '
              'reversal was validated — the payment reversal already '
              'completed, but the schedule needs a manual Edit Loan Terms '
              'correction',
        );
      }
    }

    final freshLoanSnap = await _loanRef(loan.id).get();
    final freshLoan = freshLoanSnap.data();
    if (freshLoan == null) {
      return const PaymentReversalResult(
        alreadyReversed: false,
        scheduleRestored: false,
        scheduleRestorationSkippedReason: 'Loan could not be found',
      );
    }

    final batch = _firestore.batch();
    for (final installmentId in freshEvent.retiredInstallmentIds) {
      final snap = await _installments(loan.scheduleId).doc(installmentId).get();
      final installment = snap.data();
      if (installment == null) continue;
      installment.restoreFromTrash();
      batch.set(_installments(loan.scheduleId).doc(installmentId), installment);
    }
    for (final installmentId in freshEvent.generatedInstallmentIds) {
      final snap = await _installments(loan.scheduleId).doc(installmentId).get();
      final installment = snap.data();
      if (installment == null) continue;
      installment.markDeleted();
      batch.set(_installments(loan.scheduleId).doc(installmentId), installment);
    }

    freshLoan.recordEdit(
      field: 'installmentCount (reversal)',
      oldValue: freshLoan.installmentCount.toString(),
      newValue: freshEvent.installmentCountBefore.toString(),
    );
    freshLoan.installmentCount = freshEvent.installmentCountBefore;
    batch.set(_loanRef(loan.id), freshLoan);

    if (freshEvent.scheduleTotalAmountBefore != null) {
      final scheduleSnap = await _scheduleRef(loan.scheduleId).get();
      final schedule = scheduleSnap.data();
      if (schedule != null) {
        schedule.installmentCount = freshEvent.installmentCountBefore;
        schedule.totalAmount = freshEvent.scheduleTotalAmountBefore!;
        batch.set(_scheduleRef(loan.scheduleId), schedule);
      }
    }

    freshEvent.reversed = true;
    freshEvent.reversedAt = DateTime.now();
    freshEvent.reversalId = reversalIdempotencyKey;
    batch.set(_reamortizationEvents(loan.id).doc(freshEvent.id), freshEvent);

    await batch.commit();

    return const PaymentReversalResult(
      alreadyReversed: false,
      scheduleRestored: true,
    );
  }

  /// Re-reads the schedule post-payment, solves via [policy], and — only on
  /// a definite [PrepaymentReamortizationSolved] — applies it through one
  /// `writeBatch`: soft-deletes the untouched tail, regenerates it at the
  /// solved count, updates the loan/schedule, and writes the audit event.
  /// Never called when there's nothing left to re-amortize or the solve
  /// refuses to guess — the payment itself is already committed regardless.
  Future<PrepaymentReamortizationOutcome?> _reamortize({
    required Loan loan,
    required List<Installment> scheduleInstallments,
    required String triggeringPaymentId,
    required String triggeringInstallmentId,
    required double triggeringPrepaymentAmount,
    required DateTime date,
  }) async {
    // Read phase — fresh Loan alongside fresh installments, both before any
    // writeBatch writes are queued below. loanAmount/interest/
    // installmentFrequency/loanDate/installmentCount are all mutable
    // loan-term fields (see Loan's own doc comments), so the caller-supplied
    // [loan] parameter is only trusted for its immutable fields (id,
    // scheduleId) from here on — every financial/term field used by this
    // method's calculation, AND the object written back to Firestore at the
    // end, must be this freshly-read copy. Using the stale [loan] parameter
    // for the final `batch.set` would silently regress a concurrently
    // updated field (e.g. loanAmount) back to its old value, not just
    // miscompute — see the regression test for the exact reproduction.
    final freshLoanSnap = await _loanRef(loan.id).get();
    final freshLoan = freshLoanSnap.data();
    if (freshLoan == null) {
      return const PrepaymentReamortizationUnsolvable(
        'Loan could not be found for re-amortization',
      );
    }

    // `deletedAt` must be filtered here: an EARLIER re-amortization on this
    // same loan (a prior prepayment or disbursement) soft-deletes its own
    // "untouched" tail when generating a new one — an unfiltered read would
    // resurrect those already-retired documents into THIS solve's
    // `untouched` set (they have `amountPaid == 0`/`isSkipped == false`,
    // same as a genuinely untouched installment), inflating the count and
    // silently duplicating the schedule. See the disbursement-after-
    // prepayment regression test for the exact reproduction.
    final freshSnapshot = await _installments(
      loan.scheduleId,
    ).where('deletedAt', isNull: true).get();
    final fresh = freshSnapshot.docs.map((d) => d.data()).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    final settled = fresh
        .where((i) => i.amountPaid > 0 || i.isSkipped)
        .toList();
    final untouched = fresh
        .where((i) => i.amountPaid == 0 && !i.isSkipped)
        .toList();

    if (untouched.isEmpty) {
      // The classification scope already covered the entire remaining
      // schedule — nothing left to reshape (the loan is effectively fully
      // paid off by this action).
      return null;
    }

    final principalPaidViaInstallments = settled.fold(0.0, (total, i) {
      if (i.amountPaid <= 0) return total;
      final principalShare = i.principalPortion ?? i.amountDue;
      if (i.amountPaid >= i.amountDue) return total + principalShare;
      return total + principalShare * (i.amountPaid / i.amountDue);
    });
    // The prepayment overflow itself is never applied to any installment's
    // amountDue (it's recorded as a ledger-only InstallmentPayment — see
    // record()'s doc comment), so it never shows up in settled/untouched's
    // principal math above and must be subtracted here explicitly, or this
    // solve would completely ignore the money that triggered it.
    final principalPaid = principalPaidViaInstallments + triggeringPrepaymentAmount;
    final outstandingPrincipalAfter = (freshLoan.loanAmount - principalPaid)
        .clamp(0, freshLoan.loanAmount)
        .toDouble();

    final targetInstallmentAmount = untouched.first.amountDue;
    final interest = freshLoan.interest;

    final outcome = policy.solve(
      outstandingPrincipalAfter: outstandingPrincipalAfter,
      interest: interest == null
          ? null
          : ReamortizationInterestConfig(
              type: interest.type,
              ratePercent: interest.ratePercent,
              period: interest.period,
            ),
      targetInstallmentAmount: targetInstallmentAmount,
      frequency: freshLoan.installmentFrequency!,
    );

    if (outcome is! PrepaymentReamortizationSolved) return outcome;

    final batch = _firestore.batch();
    for (final installment in untouched) {
      installment.markDeleted();
      batch.set(_installments(loan.scheduleId).doc(installment.id), installment);
    }

    final remainingCount = outcome.remainingInstallmentCount;
    final lastSettled = settled.isEmpty ? null : settled.last;
    var dueDate = lastSettled == null
        ? freshLoan.installmentFrequency!.nextDueDate(freshLoan.loanDate)
        : freshLoan.installmentFrequency!.nextDueDate(lastSettled.dueDate);

    List<PrecomputedInstallmentAmount>? precomputed;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: outstandingPrincipalAfter,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: remainingCount,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(freshLoan.installmentFrequency!),
      );
      precomputed = breakdown.periods
          .map(
            (p) => PrecomputedInstallmentAmount(
              amountDue: p.paymentAmount,
              principalPortion: p.principalPortion,
              interestPortion: p.interestPortion,
            ),
          )
          .toList();
    }
    final amounts =
        precomputed ??
        _evenSplit(outstandingPrincipalAfter, remainingCount)
            .map((a) => PrecomputedInstallmentAmount(amountDue: a))
            .toList();

    var newTailTotal = 0.0;
    final generatedInstallmentIds = <String>[];
    for (var i = 0; i < remainingCount; i++) {
      if (i > 0) dueDate = freshLoan.installmentFrequency!.nextDueDate(dueDate);
      final newInstallment = Installment(
        id: IdGenerator.generate(),
        scheduleId: loan.scheduleId,
        ownerType: untouched.first.ownerType,
        ownerId: loan.id,
        sequenceNumber: settled.length + i + 1,
        dueDate: dueDate,
        amountDue: amounts[i].amountDue,
        principalPortion: amounts[i].principalPortion,
        interestPortion: amounts[i].interestPortion,
        createdAt: DateTime.now(),
      );
      newTailTotal += amounts[i].amountDue;
      generatedInstallmentIds.add(newInstallment.id);
      batch.set(
        _installments(loan.scheduleId).doc(newInstallment.id),
        newInstallment,
      );
    }

    final newInstallmentCount = settled.length + remainingCount;
    final installmentCountBefore = freshLoan.installmentCount ?? fresh.length;
    freshLoan.recordEdit(
      field: 'installmentCount (reamortized)',
      oldValue: freshLoan.installmentCount.toString(),
      newValue: newInstallmentCount.toString(),
    );
    freshLoan.installmentCount = newInstallmentCount;
    // Writes back freshLoan (not the caller's possibly-stale `loan` param)
    // so a concurrently-changed field (e.g. loanAmount) is never silently
    // regressed to its old value by this batch.
    batch.set(_loanRef(loan.id), freshLoan);

    final settledTotal = settled.fold(0.0, (total, i) => total + i.amountDue);
    final scheduleSnap = await _scheduleRef(loan.scheduleId).get();
    final schedule = scheduleSnap.data();
    final scheduleTotalAmountBefore = schedule?.totalAmount;
    if (schedule != null) {
      schedule.installmentCount = newInstallmentCount;
      schedule.totalAmount = settledTotal + newTailTotal;
      batch.set(_scheduleRef(loan.scheduleId), schedule);
    }

    final eventId = IdGenerator.generate();
    final event = LoanReamortizationEvent(
      id: eventId,
      loanId: loan.id,
      triggerType: ReamortizationTriggerType.prepayment,
      triggeredByPaymentId: triggeringPaymentId,
      principalBefore: outstandingPrincipalAfter + triggeringPrepaymentAmount,
      principalAfter: outstandingPrincipalAfter,
      installmentCountBefore: installmentCountBefore,
      installmentCountAfter: newInstallmentCount,
      date: date,
      createdAt: DateTime.now(),
      retiredInstallmentIds: untouched.map((i) => i.id).toList(),
      generatedInstallmentIds: generatedInstallmentIds,
      scheduleTotalAmountBefore: scheduleTotalAmountBefore,
    );
    batch.set(_reamortizationEvents(loan.id).doc(eventId), event);

    await batch.commit();

    // Best-effort metadata annotation on the triggering payment doc — not
    // balance-affecting, so a failure here doesn't need to roll anything
    // back (mirrors PaymentAttributionService's own best-effort posture).
    try {
      final ref = _paymentRef(
        loan.scheduleId,
        triggeringInstallmentId,
        triggeringPaymentId,
      );
      final overflowSnap = await ref.get();
      if (overflowSnap.exists) {
        await ref.update({
          'prepaymentPolicyApplied': 'reduceTenure',
          'reamortizationEventId': eventId,
        });
      }
    } catch (_) {
      // Non-fatal — the payment and re-amortization are already correctly
      // recorded; only this cross-reference annotation is missing.
    }

    return outcome;
  }

  /// Re-amortizes the untouched tail after an additional disbursement, via
  /// [disbursementPolicy] — the disbursement counterpart of [_reamortize].
  /// Holds the remaining installment COUNT constant (the opposite fixed
  /// point from [_reamortize]'s [ReduceTenurePolicy], which holds the
  /// amount constant and solves for count) and recalculates the required
  /// installment amount for the new, larger outstanding principal. Same
  /// fresh-read discipline as [_reamortize]: never trusts the caller's
  /// possibly-stale [loan] parameter for financial fields, re-reads Loan and
  /// every installment fresh, and writes back the freshly-read Loan (not the
  /// caller's copy) so a concurrently-changed field is never regressed.
  Future<DisbursementReamortizationOutcome?> _reamortizeForDisbursement({
    required Loan loan,
    required String triggeringDisbursementId,
    required double disbursementAmount,
    required DateTime date,
  }) async {
    final freshLoanSnap = await _loanRef(loan.id).get();
    final freshLoan = freshLoanSnap.data();
    if (freshLoan == null) {
      return const DisbursementReamortizationUnsolvable(
        'Loan could not be found for re-amortization',
      );
    }
    final loanAmountBeforeDisbursement = freshLoan.loanAmount - disbursementAmount;

    // `deletedAt` must be filtered here — see `_reamortize`'s identical
    // filtered read for why: an earlier re-amortization on this loan (a
    // prior prepayment or disbursement) soft-deletes its own "untouched"
    // tail, and an unfiltered read would resurrect those already-retired
    // documents into THIS solve's `untouched` set.
    final freshSnapshot = await _installments(
      loan.scheduleId,
    ).where('deletedAt', isNull: true).get();
    final fresh = freshSnapshot.docs.map((d) => d.data()).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    final settled = fresh
        .where((i) => i.amountPaid > 0 || i.isSkipped)
        .toList();
    final untouched = fresh
        .where((i) => i.amountPaid == 0 && !i.isSkipped)
        .toList();

    if (untouched.isEmpty) {
      // Nothing left to reshape — every installment is already settled or
      // skipped. The disbursement is still correctly recorded on the Loan.
      return null;
    }

    final principalPaidViaInstallments = settled.fold(0.0, (total, i) {
      if (i.amountPaid <= 0) return total;
      final principalShare = i.principalPortion ?? i.amountDue;
      if (i.amountPaid >= i.amountDue) return total + principalShare;
      return total + principalShare * (i.amountPaid / i.amountDue);
    });
    final outstandingPrincipalAfter =
        (freshLoan.loanAmount - principalPaidViaInstallments)
            .clamp(0, freshLoan.loanAmount)
            .toDouble();

    final interest = freshLoan.interest;
    final outcome = disbursementPolicy.solve(
      outstandingPrincipalAfter: outstandingPrincipalAfter,
      interest: interest == null
          ? null
          : ReamortizationInterestConfig(
              type: interest.type,
              ratePercent: interest.ratePercent,
              period: interest.period,
            ),
      remainingInstallmentCount: untouched.length,
      frequency: freshLoan.installmentFrequency!,
    );

    if (outcome is! DisbursementReamortizationSolved) return outcome;

    final batch = _firestore.batch();
    for (final installment in untouched) {
      installment.markDeleted();
      batch.set(_installments(loan.scheduleId).doc(installment.id), installment);
    }

    final remainingCount = outcome.remainingInstallmentCount;
    final lastSettled = settled.isEmpty ? null : settled.last;
    var dueDate = lastSettled == null
        ? freshLoan.installmentFrequency!.nextDueDate(freshLoan.loanDate)
        : freshLoan.installmentFrequency!.nextDueDate(lastSettled.dueDate);

    List<PrecomputedInstallmentAmount>? precomputed;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: outstandingPrincipalAfter,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: remainingCount,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(freshLoan.installmentFrequency!),
      );
      precomputed = breakdown.periods
          .map(
            (p) => PrecomputedInstallmentAmount(
              amountDue: p.paymentAmount,
              principalPortion: p.principalPortion,
              interestPortion: p.interestPortion,
            ),
          )
          .toList();
    }
    final amounts =
        precomputed ??
        _evenSplit(outstandingPrincipalAfter, remainingCount)
            .map((a) => PrecomputedInstallmentAmount(amountDue: a))
            .toList();

    var newTailTotal = 0.0;
    final generatedInstallmentIds = <String>[];
    for (var i = 0; i < remainingCount; i++) {
      if (i > 0) dueDate = freshLoan.installmentFrequency!.nextDueDate(dueDate);
      final newInstallment = Installment(
        id: IdGenerator.generate(),
        scheduleId: loan.scheduleId,
        ownerType: untouched.first.ownerType,
        ownerId: loan.id,
        sequenceNumber: settled.length + i + 1,
        dueDate: dueDate,
        amountDue: amounts[i].amountDue,
        principalPortion: amounts[i].principalPortion,
        interestPortion: amounts[i].interestPortion,
        createdAt: DateTime.now(),
      );
      newTailTotal += amounts[i].amountDue;
      generatedInstallmentIds.add(newInstallment.id);
      batch.set(
        _installments(loan.scheduleId).doc(newInstallment.id),
        newInstallment,
      );
    }

    // remainingCount is held constant by definition (HoldTenurePolicy), so
    // the total installment count never changes here — unlike
    // `_reamortize`'s prepayment path, where it can shrink.
    final newInstallmentCount = settled.length + remainingCount;
    final installmentCountBefore = freshLoan.installmentCount ?? fresh.length;
    if (newInstallmentCount != installmentCountBefore) {
      freshLoan.recordEdit(
        field: 'installmentCount (disbursement reamortized)',
        oldValue: freshLoan.installmentCount.toString(),
        newValue: newInstallmentCount.toString(),
      );
      freshLoan.installmentCount = newInstallmentCount;
    }
    // Writes back freshLoan (already carries the disbursement's loanAmount
    // bump from the atomic core, re-read fresh here) so a concurrently
    // changed field is never silently regressed by this batch.
    batch.set(_loanRef(loan.id), freshLoan);

    final settledTotal = settled.fold(0.0, (total, i) => total + i.amountDue);
    final scheduleSnap = await _scheduleRef(loan.scheduleId).get();
    final schedule = scheduleSnap.data();
    final scheduleTotalAmountBefore = schedule?.totalAmount;
    if (schedule != null) {
      schedule.installmentCount = newInstallmentCount;
      schedule.totalAmount = settledTotal + newTailTotal;
      batch.set(_scheduleRef(loan.scheduleId), schedule);
    }

    final eventId = IdGenerator.generate();
    final event = LoanReamortizationEvent(
      id: eventId,
      loanId: loan.id,
      triggerType: ReamortizationTriggerType.additionalDisbursement,
      triggeredByDisbursementId: triggeringDisbursementId,
      principalBefore: outstandingPrincipalAfter - disbursementAmount,
      principalAfter: outstandingPrincipalAfter,
      installmentCountBefore: installmentCountBefore,
      installmentCountAfter: newInstallmentCount,
      date: date,
      createdAt: DateTime.now(),
      retiredInstallmentIds: untouched.map((i) => i.id).toList(),
      generatedInstallmentIds: generatedInstallmentIds,
      scheduleTotalAmountBefore: scheduleTotalAmountBefore,
      loanAmountBefore: loanAmountBeforeDisbursement,
    );
    batch.set(_reamortizationEvents(loan.id).doc(eventId), event);

    await batch.commit();

    // Best-effort metadata annotation — not balance-affecting.
    try {
      await _disbursements(loan.id).doc(triggeringDisbursementId).update({
        'reamortizationEventId': eventId,
      });
    } catch (_) {
      // Non-fatal — the disbursement and re-amortization are already
      // correctly recorded; only this cross-reference annotation is missing.
    }

    return outcome;
  }

  List<double> _evenSplit(double total, int count) {
    final share = _round2(total / count);
    final shares = List.filled(count, share);
    final remainder = _round2(total - share * count);
    shares[count - 1] = _round2(shares[count - 1] + remainder);
    return shares;
  }

  /// Mirrors `LoanRepository._installmentsPerYearFor` — weekly gets its own
  /// exact value (52) instead of being forced through the monthly bucket.
  int _installmentsPerYearFor(ScheduleType scheduleType) {
    switch (scheduleType) {
      case ScheduleType.weekly:
        return 52;
      case ScheduleType.monthly:
      case ScheduleType.oneTime:
      case ScheduleType.custom:
        return 12;
    }
  }

  double _round2(double v) => (v * 100).round() / 100;
}

class _CoreResult {
  const _CoreResult({
    required this.alreadyRecorded,
    required this.paymentIds,
    required this.installmentIds,
    required this.overflowPaymentId,
    required this.overflowInstallmentId,
    required this.overallType,
    required this.prepaymentPrincipalAmount,
  });

  final bool alreadyRecorded;
  final List<String> paymentIds;
  final List<String> installmentIds;
  final String? overflowPaymentId;
  final String? overflowInstallmentId;
  final PaymentAllocationType overallType;
  final double? prepaymentPrincipalAmount;
}

class _DisbursementCoreResult {
  const _DisbursementCoreResult({
    required this.alreadyRecorded,
    required this.disbursementId,
  });

  final bool alreadyRecorded;
  final String disbursementId;
}
