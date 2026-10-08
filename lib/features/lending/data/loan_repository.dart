import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentReference;

import '../../../core/constants/firestore_constants.dart';
import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/interest/interest_calculator.dart';
import '../../../core/interest/interest_period.dart';
import '../../../core/payment_schedule/data/installment_repository.dart';
import '../../../core/payment_schedule/data/payment_schedule_repository.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/owner_type.dart';
import '../../../core/payment_schedule/domain/payment_schedule.dart';
import '../../../core/payment_schedule/domain/precomputed_installment_amount.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../core/services/reminder_notification_service.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/reminder_offset_label.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/account_type.dart';
import '../../transactions/domain/transaction.dart' as domain;
import '../../transactions/domain/transaction_type.dart';
import '../domain/loan.dart';
import '../domain/loan_category.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_interest.dart';
import '../domain/loan_origination.dart';
import '../domain/loan_principal.dart';
import '../domain/loan_repayment_type.dart';

/// Fixed reminder offsets for Loans, mirroring EMI's `_emiReminderOffsets`
/// exactly: 7/3 days before (due soon), the day of (due today), and 1/3 days
/// after (overdue, negative offsets — see
/// `ReminderNotificationService.reschedule`'s doc comment). Applies to both
/// repayment types: an installment loan's "next due date" is its next
/// unpaid installment; a one-time loan's is simply [Loan.dueDate] itself.
/// No per-loan picker in this milestone, same posture as EMI.
const _loanReminderOffsets = [7, 3, 1, 0, -1, -3];

/// Loan-specific persistence on top of the generic CRUD/soft-delete
/// repository. Bridges the feature-agnostic `PaymentScheduleRepository`/
/// `InstallmentRepository` (payment tracking) and `InterestCalculator`
/// (interest math) — neither of those core engines knows what a "loan" is;
/// this repository is where the two are composed.
class LoanRepository extends FirestoreCrudRepository<Loan> {
  LoanRepository(
    super.collection,
    this.paymentScheduleRepository,
    this._installmentRepositoryFor,
  );

  final PaymentScheduleRepository paymentScheduleRepository;

  /// Resolves an `InstallmentRepository` scoped to a given schedule id —
  /// installment collections are schedule-scoped, so this is supplied by
  /// the provider layer (which owns Riverpod's per-schedule repository
  /// instances) rather than constructed directly here.
  final InstallmentRepository Function(String scheduleId)
  _installmentRepositoryFor;

  Future<Loan> createLoan({
    required double loanAmount,
    required DateTime loanDate,
    DateTime? firstDueDate,
    required LoanRepaymentType repaymentType,
    String? personId,
    LoanDirection direction = LoanDirection.given,
    LoanCategory category = LoanCategory.personal,
    String? institutionName,
    String? loanType,
    String? loanNumber,
    String? accountNumber,
    String? branch,
    String? payerPersonId,
    String? name,
    LoanInterest? interest,
    DateTime? dueDate,
    ScheduleType? installmentFrequency,
    int? installmentCount,
    String notes = '',
    LoanAgreementKind agreementKind = LoanAgreementKind.loan,
    LoanFundingSource? fundingSource,
    String? linkedCreditCardId,
    String? purchaseTransactionId,
    double? purchaseAmount,
    double? downPayment,
  }) async {
    final request = _CreateLoanRequest(
      loanAmount: loanAmount,
      loanDate: loanDate,
      firstDueDate: firstDueDate ?? loanDate,
      repaymentType: repaymentType,
      personId: personId,
      direction: direction,
      category: category,
      institutionName: institutionName,
      loanType: loanType,
      loanNumber: loanNumber,
      accountNumber: accountNumber,
      branch: branch,
      payerPersonId: payerPersonId,
      name: name,
      interest: interest,
      dueDate: dueDate,
      installmentFrequency: installmentFrequency,
      installmentCount: installmentCount,
      notes: notes,
      agreementKind: agreementKind,
      fundingSource: fundingSource,
      linkedCreditCardId: linkedCreditCardId,
      purchaseTransactionId: purchaseTransactionId,
      purchaseAmount: purchaseAmount,
      downPayment: downPayment,
    )..validate();
    final plan = _planSchedule(request);

    final loanId = IdGenerator.generate();
    final schedule = await paymentScheduleRepository.createSchedule(
      ownerType: OwnerType.loan,
      ownerId: loanId,
      totalAmount: plan.totalAmount,
      scheduleType: plan.scheduleType,
      firstDueDate: plan.firstDueDate,
      installmentCount: plan.installmentCount,
    );

    final installments = await _installmentRepositoryFor(schedule.id)
        .generateInstallments(
          schedule,
          precomputedAmounts: plan.precomputed,
          dueDayOfMonth: plan.firstDueDate.day,
        );

    final loan = request.buildLoan(loanId, schedule.id, DateTime.now());
    await add(loan.id, loan);
    if (installments.isNotEmpty) {
      _scheduleReminders(loan, installments.first.dueDate);
    }
    return loan;
  }

  /// The canonical create path for the unified Loans & Installments wizard —
  /// with or without the real origination money movement. Loan +
  /// PaymentSchedule + every Installment + (the one origination Transaction +
  /// its Account balance change) are written in ONE Firestore
  /// `runTransaction`, so there is never a Loan without its schedule or an
  /// Account moved without its Transaction. Mirrors the web app's
  /// `LoanRepository.createAgreementWithOrigination` exactly.
  ///
  /// Idempotency is repository-level: every document id derives from
  /// [idempotencyKey] ([OriginationIds]). The Loan document is the sentinel —
  /// read inside the transaction before any write — so a retry (timeout,
  /// stale caller object, double tap, concurrent duplicate) returns the
  /// already-created result without writing anything. A retry whose request
  /// differs from what was recorded under the same key throws
  /// [OriginationConflictException].
  ///
  /// Person ledger balances are deliberately NOT mutated — the Loan's
  /// `personId` is the linkage and Net Worth already counts the principal.
  ///
  /// [beforeWrite] is a test seam for failure injection only.
  Future<AgreementOriginationResult> createAgreementWithOrigination({
    required String idempotencyKey,
    required double loanAmount,
    required DateTime loanDate,
    DateTime? firstDueDate,
    required LoanRepaymentType repaymentType,
    String? movementAccountId,
    DateTime? movementDate,
    String? personId,
    LoanDirection direction = LoanDirection.taken,
    LoanCategory category = LoanCategory.institutional,
    String? institutionName,
    String? loanType,
    String? loanNumber,
    String? accountNumber,
    String? branch,
    String? payerPersonId,
    String? name,
    LoanInterest? interest,
    DateTime? dueDate,
    ScheduleType? installmentFrequency,
    int? installmentCount,
    String notes = '',
    LoanAgreementKind agreementKind = LoanAgreementKind.loan,
    LoanFundingSource? fundingSource,
    String? linkedCreditCardId,
    String? purchaseTransactionId,
    double? purchaseAmount,
    double? downPayment,
    void Function(OriginationStage stage)? beforeWrite,
  }) async {
    final request = _CreateLoanRequest(
      loanAmount: loanAmount,
      loanDate: loanDate,
      firstDueDate: firstDueDate ?? loanDate,
      repaymentType: repaymentType,
      personId: personId,
      direction: direction,
      category: category,
      institutionName: institutionName,
      loanType: loanType,
      loanNumber: loanNumber,
      accountNumber: accountNumber,
      branch: branch,
      payerPersonId: payerPersonId,
      name: name,
      interest: interest,
      dueDate: dueDate,
      installmentFrequency: installmentFrequency,
      installmentCount: installmentCount,
      notes: notes,
      agreementKind: agreementKind,
      fundingSource: fundingSource,
      linkedCreditCardId: linkedCreditCardId,
      purchaseTransactionId: purchaseTransactionId,
      purchaseAmount: purchaseAmount,
      downPayment: downPayment,
    )..validate();
    if (agreementKind == LoanAgreementKind.installmentPurchase &&
        direction != LoanDirection.taken) {
      throw const AppException(
        'An installment purchase is always money you owe',
      );
    }
    final ids = OriginationIds(idempotencyKey);
    final movement = planOriginationMovement(
      agreementKind: agreementKind,
      direction: direction,
      loanAmount: loanAmount,
      downPayment: downPayment,
      movementAccountId: movementAccountId,
    );
    final plan = _planSchedule(request);
    if (plan.installmentCount > maxAtomicOriginationInstallments) {
      throw const AppException(
        'At most $maxAtomicOriginationInstallments payments can be created in one step',
      );
    }

    final refs = _OriginationRefs(collection, ids, movementAccountId);
    final installmentIds = [
      for (var i = 1; i <= plan.installmentCount; i++) ids.installmentId(i),
    ];

    final result = await collection.firestore
        .runTransaction<AgreementOriginationResult>((tx) async {
          // --- All reads first (Firestore transaction constraint). ---
          final existingLoan = (await tx.get(refs.loan)).data();
          final existingTransaction = (await tx.get(refs.transaction)).data();
          if (existingLoan != null) {
            _assertSameOrigination(
              request,
              movement,
              movementAccountId,
              existingLoan,
              existingTransaction,
            );
            return AgreementOriginationResult(
              alreadyCreated: true,
              loan: existingLoan,
              scheduleId: existingLoan.scheduleId,
              installmentIds: installmentIds,
              transactionId: existingTransaction?.id,
              movement: movement,
            );
          }
          if (existingTransaction != null) {
            throw const OriginationConflictException(
              'An origination Transaction already exists for this key without its Loan',
            );
          }

          final account = refs.account == null
              ? null
              : _checkedMovementAccount((await tx.get(refs.account!)).data());
          if (purchaseTransactionId != null) {
            final card = (await tx.get(
              refs.userDoc
                  .collection(FirestoreCollections.creditCards)
                  .doc(linkedCreditCardId),
            )).data();
            if (card == null) throw const AppException('Credit card not found');
            final purchase = (await tx.get(
              refs.transactions.doc(purchaseTransactionId),
            )).data();
            if (purchase == null) {
              throw const AppException('Card purchase not found');
            }
            if (purchase.isDeleted ||
                purchase.type != TransactionType.expense ||
                purchase.accountId != card['accountId']) {
              throw const AppException(
                'The linked purchase must be an active expense on this credit card',
              );
            }
          }

          // --- Then all writes. ---
          final now = DateTime.now();
          beforeWrite?.call(OriginationStage.loan);
          final loan = request.buildLoan(ids.loanId, ids.scheduleId, now);
          tx.set(refs.loan, loan);

          beforeWrite?.call(OriginationStage.schedule);
          final schedule = PaymentSchedule(
            id: ids.scheduleId,
            ownerType: OwnerType.loan,
            ownerId: ids.loanId,
            totalAmount: plan.totalAmount,
            scheduleType: plan.scheduleType,
            firstDueDate: plan.firstDueDate,
            installmentCount: plan.installmentCount,
            createdAt: now,
          );
          tx.set(refs.schedule, schedule);

          beforeWrite?.call(OriginationStage.installments);
          final installments = InstallmentRepository.buildInstallments(
            schedule,
            precomputedAmounts: plan.precomputed,
            dueDayOfMonth: plan.firstDueDate.day,
            idFor: ids.installmentId,
          );
          for (final installment in installments) {
            tx.set(refs.installments.doc(installment.id), installment);
          }

          if (movement != null && account != null) {
            beforeWrite?.call(OriginationStage.transaction);
            tx.set(
              refs.transaction,
              domain.Transaction(
                id: ids.transactionId,
                type: movement.transactionType,
                amount: movement.amount,
                dateTime: movementDate ?? loanDate,
                accountId: account.id,
                categoryId: 'loan_payment',
                description: originationDescription(movement.kind, name),
                createdAt: now,
                source: 'manual',
                loanId: ids.loanId,
                paymentAllocationType: movement.allocationType,
              ),
            );

            beforeWrite?.call(OriginationStage.account);
            final newBalance = account.currentBalance + movement.balanceDelta;
            account.recordEdit(
              field: 'currentBalance',
              oldValue: account.currentBalance.toString(),
              newValue: newBalance.toString(),
            );
            account.currentBalance = newBalance;
            tx.set(refs.account!, account);
          }

          return AgreementOriginationResult(
            alreadyCreated: false,
            loan: loan,
            scheduleId: ids.scheduleId,
            installmentIds: [for (final i in installments) i.id],
            transactionId: movement == null ? null : ids.transactionId,
            movement: movement,
          );
        });

    if (!result.alreadyCreated) {
      _scheduleReminders(result.loan, plan.firstDueDate);
    }
    return result;
  }

  /// "Reverse Loan Creation" — undoes an origination as a whole: soft-deletes
  /// the origination Transaction (reversing its Account balance effect exactly
  /// once) and trashes the Loan, in ONE `runTransaction`. The
  /// schedule/installments stay with the trashed Loan. Mirrors the web app's
  /// `LoanRepository.reverseOrigination`.
  ///
  /// Refused with [OriginationReversalBlockedException] once anything else has
  /// happened on the agreement — any installment payment (even one later
  /// reversed), any Borrow/Lend More, any re-amortization or schedule edit
  /// (Edit Terms / Loan Date / skip), a principal edit, or closing it.
  /// Installments are re-read inside the transaction, so a racing payment is
  /// caught too.
  ///
  /// Idempotent: returns `true` ("already reversed") without writing once the
  /// Loan is trashed and its Transaction (if any) deleted. Also recovers a Loan
  /// an older app trashed while its money was still active. [beforeWrite] is
  /// a test seam for failure injection only.
  Future<bool> reverseOrigination(
    String idempotencyKey, {
    void Function()? beforeWrite,
  }) async {
    final ids = OriginationIds(idempotencyKey);
    final refs = _OriginationRefs(collection, ids, null);
    final loan = (await refs.loan.get()).data();
    if (loan == null) throw const NotFoundException('Loan not found');

    // Retry fast path: already fully reversed → nothing to check or write.
    final existingTransaction = (await refs.transaction.get()).data();
    if (loan.isDeleted &&
        (existingTransaction == null || existingTransaction.isDeleted)) {
      return true;
    }

    // Dependency guard (queries can't run inside a transaction). Any
    // payment/disbursement/re-plan record blocks, active or reversed.
    final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
    final installments = [
      ...await installmentRepository.getAll(),
      ...await installmentRepository.getTrash(),
    ];
    final loanDoc = refs.userDoc
        .collection(FirestoreCollections.loans)
        .doc(loan.id);
    for (final installment in installments) {
      final payments = await refs.userDoc
          .collection(FirestoreCollections.paymentSchedules)
          .doc(loan.scheduleId)
          .collection(FirestoreCollections.installments)
          .doc(installment.id)
          .collection(FirestoreCollections.payments)
          .get();
      if (payments.docs.isNotEmpty) {
        throw OriginationReversalBlockedException(
          OriginationReversalBlockReason.payment,
        );
      }
    }
    if ((await loanDoc
            .collection(FirestoreCollections.additionalDisbursements)
            .get())
        .docs
        .isNotEmpty) {
      throw OriginationReversalBlockedException(
        OriginationReversalBlockReason.disbursement,
      );
    }
    if ((await loanDoc
            .collection(FirestoreCollections.reamortizationEvents)
            .get())
        .docs
        .isNotEmpty) {
      throw OriginationReversalBlockedException(
        OriginationReversalBlockReason.scheduleChanged,
      );
    }
    final originalCount = loan.repaymentType == LoanRepaymentType.oneTime
        ? 1
        : loan.installmentCount;
    final scheduleIntact =
        installments.length == originalCount &&
        installments.every(
          (i) => i.id == ids.installmentId(i.sequenceNumber) && !i.isDeleted,
        );
    if (!scheduleIntact) {
      throw OriginationReversalBlockedException(
        OriginationReversalBlockReason.scheduleChanged,
      );
    }
    final installmentsRef = refs.userDoc
        .collection(FirestoreCollections.paymentSchedules)
        .doc(loan.scheduleId)
        .collection(FirestoreCollections.installments)
        .withConverter<Installment>(
          fromFirestore: Installment.fromFirestore,
          toFirestore: (i, _) => i.toFirestore(),
        );

    final alreadyReversed = await collection.firestore.runTransaction<bool>((
      tx,
    ) async {
      // --- All reads first. ---
      final freshLoan = (await tx.get(refs.loan)).data();
      if (freshLoan == null) {
        throw const NotFoundException('Loan not found');
      }
      final transaction = (await tx.get(refs.transaction)).data();
      final moneyStillMoved = transaction != null && !transaction.isDeleted;
      if (freshLoan.isDeleted && !moneyStillMoved) return true;
      _assertReversibleLoan(freshLoan);

      final accountRef = moneyStillMoved
          ? refs.accounts.doc(transaction.accountId)
          : null;
      final account = accountRef == null
          ? null
          : (await tx.get(accountRef)).data();
      if (accountRef != null && account == null) {
        throw const AppException('Account not found');
      }
      for (final installment in installments) {
        final fresh = (await tx.get(
          installmentsRef.doc(installment.id),
        )).data();
        if (fresh == null || fresh.isDeleted || fresh.isSkipped) {
          throw OriginationReversalBlockedException(
            OriginationReversalBlockReason.scheduleChanged,
          );
        }
        if (fresh.amountPaid != 0) {
          throw OriginationReversalBlockedException(
            OriginationReversalBlockReason.payment,
          );
        }
      }

      // --- Then all writes. ---
      beforeWrite?.call();
      if (moneyStillMoved && account != null) {
        final newBalance = account.currentBalance - transaction.balanceEffect;
        account.recordEdit(
          field: 'currentBalance',
          oldValue: account.currentBalance.toString(),
          newValue: newBalance.toString(),
        );
        account.currentBalance = newBalance;
        tx.set(accountRef!, account);
        transaction.markDeleted();
        tx.set(refs.transaction, transaction);
      }
      if (!freshLoan.isDeleted) {
        freshLoan.markDeleted();
        tx.set(refs.loan, freshLoan);
      }
      return false;
    });
    if (!alreadyReversed) _cancelReminders(loan.id);
    return alreadyReversed;
  }

  /// The money state of this Loan's origination, read from its deterministic
  /// Transaction id.
  Future<OriginationMoneyState> originationMoneyState(Loan loan) async {
    final key = originationKeyFromLoanId(loan.id);
    if (key == null) return OriginationMoneyState.notOriginated;
    final refs = _OriginationRefs(collection, OriginationIds(key), null);
    final transaction = (await refs.transaction.get()).data();
    if (transaction == null) return OriginationMoneyState.noMovement;
    return transaction.isDeleted
        ? OriginationMoneyState.moneyReversed
        : OriginationMoneyState.moneyActive;
  }

  /// The origination money movement that is still active on [loan], or null
  /// (legacy Loan, no movement recorded, or already reversed). Feeds the
  /// "Reverse & Delete" confirmation.
  Future<({OriginationMovementKind kind, double amount, String accountId})?>
  activeOriginationMovement(Loan loan) async {
    final key = originationKeyFromLoanId(loan.id);
    if (key == null) return null;
    final transaction = (await _OriginationRefs(
      collection,
      OriginationIds(key),
      null,
    ).transaction.get()).data();
    if (transaction == null || transaction.isDeleted) return null;
    return (
      kind: originationMovementKindOf(
        type: transaction.type,
        paymentAllocationType: transaction.paymentAllocationType,
      ),
      amount: transaction.amount,
      accountId: transaction.accountId,
    );
  }

  /// Trash. A Loan whose origination money is still active can't be trashed
  /// on its own — Trash removes it from Net Worth while its cash would stay —
  /// so it must go through [reverseOrigination] ("Reverse & Delete").
  @override
  Future<void> softDelete(Loan entity) async {
    if (await originationMoneyState(entity) ==
        OriginationMoneyState.moneyActive) {
      throw const OriginationDeleteBlockedException(reverseFirst: true);
    }
    await super.softDelete(entity);
  }

  /// Restore from Trash. A Loan whose origination money was reversed stays
  /// reversed: restoring it would bring the debt/receivable back without the
  /// money that created it.
  @override
  Future<void> restore(Loan entity) async {
    if (await originationMoneyState(entity) ==
        OriginationMoneyState.moneyReversed) {
      throw const OriginationDeleteBlockedException(reverseFirst: false);
    }
    await super.restore(entity);
  }

  static void _assertReversibleLoan(Loan loan) {
    if (loan.isClosed) {
      throw OriginationReversalBlockedException(
        OriginationReversalBlockReason.closed,
      );
    }
    final changed = loan.editHistory.any(
      (e) =>
          e.field.startsWith('loanAmount') ||
          e.field == 'loanTerms' ||
          e.field == 'loanDate',
    );
    if (changed) {
      throw OriginationReversalBlockedException(
        OriginationReversalBlockReason.scheduleChanged,
      );
    }
  }

  _SchedulePlan _planSchedule(_CreateLoanRequest request) {
    final shape = originationScheduleShape(
      request.repaymentType,
      request.installmentFrequency,
      request.installmentCount,
    );

    List<PrecomputedInstallmentAmount>? precomputed;
    final interest = request.interest;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: request.loanAmount,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: shape.installmentCount,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(shape.scheduleType),
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
    return _SchedulePlan(
      installmentCount: shape.installmentCount,
      scheduleType: shape.scheduleType,
      firstDueDate: request.repaymentType == LoanRepaymentType.oneTime
          ? request.dueDate!
          : request.firstDueDate,
      precomputed: precomputed,
      totalAmount: precomputed == null
          ? request.loanAmount
          : precomputed.fold(0.0, (sum, p) => sum + p.amountDue),
    );
  }

  /// A retry under the same key must describe the same agreement and the same
  /// money movement. Only creation-immutable Loan facts are compared (terms
  /// may since have been edited legitimately), plus the origination
  /// Transaction's presence/account/amount.
  static void _assertSameOrigination(
    _CreateLoanRequest requested,
    OriginationMovement? movement,
    String? movementAccountId,
    Loan existing,
    domain.Transaction? existingTransaction,
  ) {
    final sameAgreement =
        existing.direction == requested.direction &&
        existing.agreementKind == requested.agreementKind &&
        existing.repaymentType == requested.repaymentType &&
        existing.category == requested.category;
    final sameMovement = movement == null
        ? existingTransaction == null
        : existingTransaction != null &&
              existingTransaction.accountId == movementAccountId &&
              (existingTransaction.amount - movement.amount).abs() < 0.005;
    if (!sameAgreement || !sameMovement) {
      throw const OriginationConflictException(
        'This request was already used to create a different agreement',
      );
    }
  }

  static Account _checkedMovementAccount(Account? account) {
    if (account == null || account.isDeleted) {
      throw const AppException('Account not found');
    }
    // Card accounts are excluded: borrowing into / lending from a card is the
    // separate, not-yet-supported "my card used for someone else" flow, and a
    // card purchase is linked, never re-recorded.
    if (account.type == AccountType.card) {
      throw const AppException(
        'Choose a bank, cash or wallet account for this money movement',
      );
    }
    return account;
  }

  /// [name]/[notes]/[dueDate] (one-time loans only) are editable
  /// post-creation. [loanAmount] locks once [hasPayments] is true (mirrors
  /// `Person.openingBalance`/`Account.openingBalance`'s immutable-after-use
  /// posture). [repaymentType]/[interest]/[installmentFrequency]/
  /// [installmentCount] are never editable — they drive the one-shot
  /// schedule/installment generation in [createLoan], with no "regenerate"
  /// path, so this method doesn't accept them at all.
  Future<void> editLoan(
    Loan loan, {
    required bool hasPayments,
    String? name,
    double? loanAmount,
    DateTime? dueDate,
    String? notes,
    String? institutionName,
    String? loanType,
    String? loanNumber,
    String? accountNumber,
    String? branch,
    String? payerPersonId,
  }) async {
    if (loanAmount != null) {
      if (loanAmount <= 0) {
        throw const AppException('Loan amount must be greater than 0');
      }
      if (hasPayments) {
        throw const AppException(
          'Loan amount cannot be changed after a payment has been recorded',
        );
      }
    }
    if (dueDate != null && loan.repaymentType != LoanRepaymentType.oneTime) {
      throw const AppException('Only one-time loans have an editable due date');
    }

    loan.updateField(
      field: 'name',
      oldValue: loan.name,
      newValue: name,
      apply: (v) => loan.name = v,
    );
    loan.updateField(
      field: 'loanAmount',
      oldValue: loan.loanAmount,
      newValue: loanAmount,
      apply: (v) => loan.loanAmount = v,
    );
    loan.updateField(
      field: 'notes',
      oldValue: loan.notes,
      newValue: notes,
      apply: (v) => loan.notes = v,
    );
    loan.updateField(
      field: 'institutionName',
      oldValue: loan.institutionName,
      newValue: institutionName,
      apply: (v) => loan.institutionName = v,
    );
    loan.updateField(
      field: 'loanType',
      oldValue: loan.loanType,
      newValue: loanType,
      apply: (v) => loan.loanType = v,
    );
    loan.updateField(
      field: 'loanNumber',
      oldValue: loan.loanNumber,
      newValue: loanNumber,
      apply: (v) => loan.loanNumber = v,
    );
    loan.updateField(
      field: 'accountNumber',
      oldValue: loan.accountNumber,
      newValue: accountNumber,
      apply: (v) => loan.accountNumber = v,
    );
    loan.updateField(
      field: 'branch',
      oldValue: loan.branch,
      newValue: branch,
      apply: (v) => loan.branch = v,
    );
    loan.updateField(
      field: 'payerPersonId',
      oldValue: loan.payerPersonId,
      newValue: payerPersonId,
      apply: (v) => loan.payerPersonId = v,
    );
    await update(loan);
  }

  /// Changes [interest]/[installmentFrequency]/[installmentCount] on an
  /// installment loan that may already have payments recorded against it.
  /// Mirrors `EmiRepository.editEmiTerms` exactly: re-amortizes the
  /// *outstanding* principal (principal already paid down, via fully- or
  /// partially-paid installments, is left alone) over the new terms and
  /// regenerates only the untouched (zero-payment) tail of the schedule.
  /// One-time loans have no "terms" of this kind — the caller should never
  /// invoke this for a [LoanRepaymentType.oneTime] loan.
  ///
  /// [currentInstallments] must be every installment currently on
  /// `loan.scheduleId`. [newInstallmentCount] must be at least the number of
  /// installments that already carry a payment.
  Future<void> editLoanTerms(
    Loan loan, {
    required List<Installment> currentInstallments,
    LoanInterest? interest,
    ScheduleType? installmentFrequency,
    required int newInstallmentCount,
  }) async {
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException('Only installment loans have editable terms');
    }
    if (newInstallmentCount < 1) {
      throw const AppException('Loan needs at least 1 payment');
    }
    if (interest != null && interest.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }

    final sorted = [...currentInstallments]
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final settled = sorted
        .where((i) => i.amountPaid > 0 || i.isSkipped)
        .toList();
    final untouched = sorted
        .where((i) => i.amountPaid == 0 && !i.isSkipped)
        .toList();

    if (newInstallmentCount < settled.length) {
      throw const AppException(
        'Number of payments can\'t be less than the payments already made',
      );
    }

    final principalPaid = settled.fold(0.0, (sum, i) {
      if (i.amountPaid <= 0) return sum;
      final principalShare = i.principalPortion ?? i.amountDue;
      // A fully-paid installment counts its whole principal share. One
      // that's only partially paid (including a partial payment later
      // skipped) counts only the principal fraction of what was actually
      // paid — crediting the full share here would overstate principal
      // paid down and understate outstandingPrincipal below.
      if (i.amountPaid >= i.amountDue) return sum + principalShare;
      return sum + principalShare * (i.amountPaid / i.amountDue);
    });
    // Extra principal already paid stays paid — derived from the persisted
    // payment records ([principalPrepaidFor]), never a stored total. Without
    // it, editing terms after an extra-principal payment re-planned the
    // schedule at the pre-prepayment principal. Mirrors Web.
    final principalPrepaid = await activePrincipalPrepaid(loan.scheduleId);
    final outstandingPrincipal =
        (loan.loanAmount - principalPaid - principalPrepaid)
            .clamp(0, loan.loanAmount)
            .toDouble();
    final remainingCount = newInstallmentCount - settled.length;

    final effectiveFrequency =
        installmentFrequency ?? loan.installmentFrequency!;

    List<Installment> newTail = const [];
    if (remainingCount > 0 && outstandingPrincipal > 0) {
      List<PrecomputedInstallmentAmount>? precomputed;
      if (interest != null) {
        final breakdown = InterestCalculator.calculate(
          principal: outstandingPrincipal,
          type: interest.type,
          ratePercent: interest.ratePercent,
          period: interest.period,
          installmentCount: remainingCount,
          installmentFrequency: InterestPeriod.monthly,
          installmentsPerYear: _installmentsPerYearFor(effectiveFrequency),
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

      final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
      await installmentRepository.replaceUnpaid(untouched);

      final lastSettled = settled.isEmpty ? null : settled.last;
      final nextDueDate = lastSettled == null
          ? effectiveFrequency.nextDueDate(loan.loanDate)
          : effectiveFrequency.nextDueDate(lastSettled.dueDate);
      final tailTotal = precomputed == null
          ? outstandingPrincipal
          : precomputed.fold(0.0, (s, p) => s + p.amountDue);

      final tailScheduleShape = PaymentSchedule(
        id: loan.scheduleId,
        ownerType: OwnerType.loan,
        ownerId: loan.id,
        totalAmount: tailTotal,
        scheduleType: effectiveFrequency,
        firstDueDate: nextDueDate,
        installmentCount: remainingCount,
        createdAt: DateTime.now(),
      );
      newTail = await installmentRepository.generateInstallments(
        tailScheduleShape,
        precomputedAmounts: precomputed,
        startingSequenceNumber: settled.length,
        dueDayOfMonth: loan.loanDate.day,
      );
    }

    loan.recordEdit(
      field: 'loanTerms',
      oldValue:
          '${loan.interest?.ratePercent}/${loan.installmentFrequency?.name}/${loan.installmentCount}',
      newValue:
          '${interest?.ratePercent}/${effectiveFrequency.name}/$newInstallmentCount',
    );
    loan.interest = interest;
    loan.installmentFrequency = effectiveFrequency;
    loan.installmentCount = newInstallmentCount;
    await update(loan);

    final schedule = await paymentScheduleRepository.getByKey(loan.scheduleId);
    if (schedule != null) {
      final settledTotal = settled.fold(0.0, (sum, i) => sum + i.amountDue);
      final newTailTotal = newTail.fold(0.0, (sum, i) => sum + i.amountDue);
      await paymentScheduleRepository.editSchedule(
        schedule,
        installmentCount: newInstallmentCount,
        totalAmount: settledTotal + newTailTotal,
      );
    }

    if (newTail.isNotEmpty) {
      rescheduleReminders(loan, newTail.first.dueDate);
    } else {
      _cancelReminders(loan.id);
    }
  }

  /// Changes [Loan.loanDate] ("Loan Date") for an installment loan — only
  /// permitted before any payment exists anywhere on the loan, mirroring
  /// `EmiRepository.editStartDate`. Regenerates every installment from
  /// scratch against the new date, reusing the loan's existing
  /// interest/frequency/count. One-time loans use [dueDate] instead, which
  /// is already editable via [editLoan].
  Future<void> editFirstDueDate(
    Loan loan, {
    required DateTime newFirstDueDate,
    required bool hasPayments,
    required List<Installment> currentInstallments,
  }) async {
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException(
        'Only installment loans have an editable First EMI Date',
      );
    }
    if (hasPayments) {
      throw const AppException(
        'First EMI Date can\'t be changed after a payment has been recorded',
      );
    }

    final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
    final liveInstallments = await installmentRepository.getAll();
    for (final installment in liveInstallments) {
      await installmentRepository.softDelete(installment);
    }

    List<PrecomputedInstallmentAmount>? precomputed;
    final interest = loan.interest;
    if (interest != null) {
      final breakdown = InterestCalculator.calculate(
        principal: loan.loanAmount,
        type: interest.type,
        ratePercent: interest.ratePercent,
        period: interest.period,
        installmentCount: loan.installmentCount!,
        installmentFrequency: InterestPeriod.monthly,
        installmentsPerYear: _installmentsPerYearFor(
          loan.installmentFrequency!,
        ),
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

    final schedule = await paymentScheduleRepository.getByKey(loan.scheduleId);
    final totalAmount = precomputed == null
        ? loan.loanAmount
        : precomputed.fold(0.0, (sum, p) => sum + p.amountDue);
    if (schedule != null) {
      await paymentScheduleRepository.editSchedule(
        schedule,
        totalAmount: totalAmount,
        firstDueDate: newFirstDueDate,
      );
    }

    final newInstallments = await installmentRepository.generateInstallments(
      PaymentSchedule(
        id: loan.scheduleId,
        ownerType: OwnerType.loan,
        ownerId: loan.id,
        totalAmount: totalAmount,
        scheduleType: loan.installmentFrequency!,
        firstDueDate: newFirstDueDate,
        installmentCount: loan.installmentCount!,
        createdAt: loan.createdAt,
      ),
      precomputedAmounts: precomputed,
      dueDayOfMonth: newFirstDueDate.day,
    );

    if (newInstallments.isNotEmpty) {
      rescheduleReminders(loan, newInstallments.first.dueDate);
    }
  }

  /// Changes when the loan was taken without moving the repayment schedule.
  Future<void> editLoanDate(
    Loan loan, {
    required DateTime newLoanDate,
    required bool hasPayments,
    required List<Installment> currentInstallments,
  }) async {
    if (loan.repaymentType != LoanRepaymentType.installment) {
      throw const AppException(
        'Only installment loans have an editable loan date',
      );
    }
    if (hasPayments) {
      throw const AppException(
        'Loan date can\'t be changed after a payment has been recorded',
      );
    }
    loan.recordEdit(
      field: 'loanDate',
      oldValue: loan.loanDate.toIso8601String(),
      newValue: newLoanDate.toIso8601String(),
    );
    loan.loanDate = newLoanDate;
    await update(loan);
  }

  Future<void> closeLoan(Loan loan) async {
    if (loan.isClosed) return;
    loan.recordEdit(field: 'isClosed', oldValue: 'false', newValue: 'true');
    loan.isClosed = true;
    await update(loan);
    _cancelReminders(loan.id);
  }

  /// [currentInstallments] lets a still-unpaid installment loan pick back up
  /// its reminders against its next unpaid due date; a one-time loan (no
  /// installments) reschedules against [Loan.dueDate] itself. Optional and
  /// defaults to empty so existing call sites that don't have the list on
  /// hand keep compiling — they simply won't get reminders restored until
  /// the next payment/edit touches this loan.
  Future<void> reopenLoan(
    Loan loan, {
    List<Installment> currentInstallments = const [],
  }) async {
    if (!loan.isClosed) return;
    loan.recordEdit(field: 'isClosed', oldValue: 'true', newValue: 'false');
    loan.isClosed = false;
    await update(loan);

    if (loan.repaymentType == LoanRepaymentType.oneTime) {
      if (loan.dueDate != null) {
        _scheduleReminders(loan, loan.dueDate!);
      }
      return;
    }
    final nextUnpaid =
        currentInstallments
            .where((i) => i.remainingAmount > 0 && !i.isSkipped)
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (nextUnpaid.isNotEmpty) {
      rescheduleReminders(loan, nextUnpaid.first.dueDate);
    }
  }

  /// Wipes [loan] and everything under it — unlike the generic inherited
  /// `permanentlyDelete` (which only removes the `loans/{loanId}` doc), this
  /// also deletes every `Installment` on the linked schedule (including
  /// already-trashed ones from a prior `editLoanTerms`/`editLoanDate`
  /// regeneration), each installment's own `payments` subcollection, and the
  /// `PaymentSchedule` document — so nothing orphaned is left in Firestore,
  /// and any reminder still scheduled against this loan is cancelled too.
  /// Mirrors `EmiRepository.permanentlyDeleteEmi` exactly. This is the
  /// method trash screens should call instead of the inherited
  /// `permanentlyDelete`.
  Future<void> permanentlyDeleteLoan(Loan loan) async {
    // Never orphan financial effects: active origination money must be
    // reversed first.
    if (await originationMoneyState(loan) ==
        OriginationMoneyState.moneyActive) {
      throw const OriginationDeleteBlockedException(reverseFirst: true);
    }
    final installmentRepository = _installmentRepositoryFor(loan.scheduleId);
    final installments = await installmentRepository.getAll();
    final trashedInstallments = await installmentRepository.getTrash();

    for (final installment in [...installments, ...trashedInstallments]) {
      final paymentsSnapshot = await installmentRepository.collection
          .doc(installment.id)
          .collection(FirestoreCollections.payments)
          .get();
      for (final paymentDoc in paymentsSnapshot.docs) {
        await paymentDoc.reference.delete();
      }
      await installmentRepository.permanentlyDelete(installment);
    }

    _cancelReminders(loan.id);

    await paymentScheduleRepository.collection.doc(loan.scheduleId).delete();
    await permanentlyDelete(loan);
  }

  /// Total active extra principal on [scheduleId], derived from persisted
  /// payment records ([principalPrepaidFor]). Reads payments under every
  /// installment, retired ones included. Public so providers computing the
  /// displayed outstanding principal use this exact derivation.
  Future<double> activePrincipalPrepaid(String scheduleId) async {
    final installmentRepository = _installmentRepositoryFor(scheduleId);
    final installments = [
      ...await installmentRepository.getAll(),
      ...await installmentRepository.getTrash(),
    ];
    final payments = <InstallmentPayment>[];
    for (final installment in installments) {
      final snap = await installmentRepository.collection
          .doc(installment.id)
          .collection(FirestoreCollections.payments)
          .withConverter<InstallmentPayment>(
            fromFirestore: InstallmentPayment.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          )
          .get();
      payments.addAll(snap.docs.map((d) => d.data()));
    }
    return principalPrepaidFor(payments);
  }

  /// Reschedules reminders against [nextDueDate] — the caller resolves this
  /// from the loan's next unpaid installment (installment loans) or its own
  /// [Loan.dueDate] (one-time loans). Exposed publicly (unlike Bills'
  /// private `_scheduleReminders`) because a loan's "next due date" changes
  /// on every payment, not just on create/edit, so the payment-recording UI
  /// needs to trigger this too — mirrors `EmiRepository.rescheduleReminders`.
  void rescheduleReminders(Loan loan, DateTime nextDueDate) =>
      _scheduleReminders(loan, nextDueDate);

  /// Cancels every reminder scheduled for [loanId] — call once a loan has
  /// nothing left to remind about (fully paid off, but not explicitly
  /// closed). Public so payment-recording UIs can call it directly when a
  /// payment leaves no unpaid installment behind, same as [rescheduleReminders].
  void cancelReminders(String loanId) => _cancelReminders(loanId);

  /// Best-effort, fire-and-forget — a notification scheduling failure must
  /// never block or fail a Firestore write, and the installment schedule
  /// stays the sole source of truth regardless of whether this succeeds.
  void _scheduleReminders(Loan loan, DateTime nextDueDate) {
    final label = loan.repaymentType == LoanRepaymentType.oneTime
        ? 'loan payment'
        : 'EMI';
    ReminderNotificationService.reschedule(
      ownerId: loan.id,
      title: loan.name?.isNotEmpty == true ? loan.name! : 'Loan',
      bodyBuilder: (offset) =>
          '${reminderOffsetLabel(offset)} — $label due ${nextDueDate.day}/${nextDueDate.month}',
      dueDate: nextDueDate,
      offsets: _loanReminderOffsets,
    ).catchError((_) {});
  }

  void _cancelReminders(String loanId) {
    ReminderNotificationService.cancel(loanId).catchError((_) {});
  }

  /// True per-installment count for [InterestCalculator]'s
  /// [installmentsPerYear] rate normalization — weekly gets its own exact
  /// value (52) instead of being forced through the monthly bucket, which
  /// previously overstated weekly interest by ~4.3x. `oneTime` never
  /// reaches [InterestCalculator]'s periodic-rate path (a single
  /// installment uses the quoted rate directly), so its value here is
  /// unused; `custom` isn't offered by the Loans form, so 12 (monthly) is
  /// a safe placeholder if that ever changes.
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
}

/// Outcome of [LoanRepository.createAgreementWithOrigination].
class AgreementOriginationResult {
  const AgreementOriginationResult({
    required this.alreadyCreated,
    required this.loan,
    required this.scheduleId,
    required this.installmentIds,
    required this.transactionId,
    required this.movement,
  });

  /// True when this idempotency key had already been used — nothing was
  /// written by this call.
  final bool alreadyCreated;
  final Loan loan;
  final String scheduleId;

  /// The installment ids the origination created (deterministic, in order).
  final List<String> installmentIds;

  /// The one origination Transaction, or null when no money moved.
  final String? transactionId;
  final OriginationMovement? movement;
}

/// Failure-injection stages for
/// [LoanRepository.createAgreementWithOrigination] (tests only).
enum OriginationStage { loan, schedule, installments, transaction, account }

/// The same idempotency key was reused for a different agreement/movement.
class OriginationConflictException extends AppException {
  const OriginationConflictException(super.message);
}

/// Why an origination can no longer be undone as a whole.
enum OriginationReversalBlockReason {
  payment,
  disbursement,
  scheduleChanged,
  closed,
}

/// Thrown when later dependent activity makes reversing an origination unsafe.
/// Same reasons and wording as the web app's `OriginationReversalBlockedError`.
class OriginationReversalBlockedException extends AppException {
  OriginationReversalBlockedException(this.reason)
    : super(switch (reason) {
        OriginationReversalBlockReason.payment =>
          'A payment has been recorded on this agreement, so its creation can no longer be reversed.',
        OriginationReversalBlockReason.disbursement =>
          'More money was added to this agreement, so its creation can no longer be reversed.',
        OriginationReversalBlockReason.scheduleChanged =>
          "This agreement's terms or schedule were changed, so its creation can no longer be reversed.",
        OriginationReversalBlockReason.closed =>
          'This agreement is closed. Reopen it before reversing its creation.',
      });

  final OriginationReversalBlockReason reason;
}

enum OriginationMoneyState {
  notOriginated,
  noMovement,
  moneyActive,
  moneyReversed,
}

/// Thrown when a plain trash / restore / permanent delete would split a Loan
/// from its origination money.
class OriginationDeleteBlockedException extends AppException {
  const OriginationDeleteBlockedException({required this.reverseFirst})
    : super(
        reverseFirst
            ? 'Money was recorded when this agreement was created. Use Reverse & Delete to undo it first.'
            : "This agreement's creation was reversed, so it can't be restored. Add it again instead.",
      );

  /// True: reverse before trashing/deleting. False: it was reversed, so it
  /// can't be restored.
  final bool reverseFirst;
}

class _SchedulePlan {
  const _SchedulePlan({
    required this.installmentCount,
    required this.scheduleType,
    required this.firstDueDate,
    required this.precomputed,
    required this.totalAmount,
  });

  final int installmentCount;
  final ScheduleType scheduleType;
  final DateTime firstDueDate;
  final List<PrecomputedInstallmentAmount>? precomputed;
  final double totalAmount;
}

/// Every create input in one place, so [LoanRepository.createLoan] and
/// [LoanRepository.createAgreementWithOrigination] share one validation and
/// one Loan-document builder.
class _CreateLoanRequest {
  const _CreateLoanRequest({
    required this.loanAmount,
    required this.loanDate,
    required this.firstDueDate,
    required this.repaymentType,
    required this.direction,
    required this.category,
    required this.notes,
    required this.agreementKind,
    this.personId,
    this.institutionName,
    this.loanType,
    this.loanNumber,
    this.accountNumber,
    this.branch,
    this.payerPersonId,
    this.name,
    this.interest,
    this.dueDate,
    this.installmentFrequency,
    this.installmentCount,
    this.fundingSource,
    this.linkedCreditCardId,
    this.purchaseTransactionId,
    this.purchaseAmount,
    this.downPayment,
  });

  final double loanAmount;
  final DateTime loanDate;
  final DateTime firstDueDate;
  final LoanRepaymentType repaymentType;
  final String? personId;
  final LoanDirection direction;
  final LoanCategory category;
  final String? institutionName;
  final String? loanType;
  final String? loanNumber;
  final String? accountNumber;
  final String? branch;
  final String? payerPersonId;
  final String? name;
  final LoanInterest? interest;
  final DateTime? dueDate;
  final ScheduleType? installmentFrequency;
  final int? installmentCount;
  final String notes;
  final LoanAgreementKind agreementKind;
  final LoanFundingSource? fundingSource;
  final String? linkedCreditCardId;
  final String? purchaseTransactionId;
  final double? purchaseAmount;
  final double? downPayment;

  void validate() {
    if (purchaseTransactionId != null && linkedCreditCardId == null) {
      throw const AppException(
        'A purchase transaction requires a tracked credit card',
      );
    }
    if (agreementKind == LoanAgreementKind.installmentPurchase) {
      final purchase = purchaseAmount;
      final down = downPayment;
      if (purchase == null || purchase <= 0) {
        throw const AppException('Purchase amount must be greater than 0');
      }
      if (down == null || down < 0 || down > purchase) {
        throw const AppException(
          'Down payment must be between 0 and the purchase amount',
        );
      }
      if ((loanAmount - (purchase - down)).abs() > 0.005) {
        throw const AppException(
          'Financed principal must equal purchase amount minus down payment',
        );
      }
    }
    if (loanAmount <= 0) {
      throw const AppException('Loan amount must be greater than 0');
    }
    if (category == LoanCategory.personal &&
        (personId == null || personId!.isEmpty)) {
      throw const AppException('Choose a person');
    }
    if (category == LoanCategory.institutional &&
        (institutionName == null || institutionName!.trim().isEmpty)) {
      throw const AppException('Institution name is required');
    }
    if (repaymentType == LoanRepaymentType.oneTime && dueDate == null) {
      throw const AppException('One-time loans need a due date');
    }
    if (repaymentType == LoanRepaymentType.installment) {
      if (installmentFrequency == null) {
        throw const AppException(
          'Monthly payment loans need a repayment frequency',
        );
      }
      if (installmentCount == null || installmentCount! < 1) {
        throw const AppException(
          'Monthly payment loans need at least 1 payment',
        );
      }
    }
    if (interest != null && interest!.ratePercent < 0) {
      throw const AppException('Interest rate cannot be negative');
    }
  }

  Loan buildLoan(String loanId, String scheduleId, DateTime createdAt) {
    // An institutional loan is never person-linked, regardless of what's
    // passed — structurally prevents the invalid "both" combination rather
    // than relying on the caller/UI alone.
    final institutional = category == LoanCategory.institutional;
    return Loan(
      id: loanId,
      agreementKind: agreementKind,
      fundingSource: fundingSource,
      linkedCreditCardId: linkedCreditCardId,
      purchaseTransactionId: purchaseTransactionId,
      purchaseAmount: purchaseAmount,
      downPayment: downPayment,
      personId: category == LoanCategory.personal ? personId : null,
      direction: direction,
      category: category,
      institutionName: institutional ? institutionName!.trim() : null,
      loanType: institutional ? loanType : null,
      loanNumber: institutional ? loanNumber : null,
      accountNumber: institutional ? accountNumber : null,
      branch: institutional ? branch : null,
      payerPersonId: payerPersonId,
      name: name,
      loanAmount: loanAmount,
      interest: interest,
      loanDate: loanDate,
      repaymentType: repaymentType,
      dueDate: repaymentType == LoanRepaymentType.oneTime ? dueDate : null,
      installmentFrequency: repaymentType == LoanRepaymentType.installment
          ? installmentFrequency
          : null,
      installmentCount: repaymentType == LoanRepaymentType.installment
          ? installmentCount
          : null,
      notes: notes,
      scheduleId: scheduleId,
      createdAt: createdAt,
    );
  }
}

/// Typed references for one origination, all derived from the key.
class _OriginationRefs {
  _OriginationRefs(
    CollectionReference<Loan> loans,
    OriginationIds ids,
    String? movementAccountId,
  ) : userDoc = loans.parent!,
      loan = loans.doc(ids.loanId) {
    schedule = userDoc
        .collection(FirestoreCollections.paymentSchedules)
        .withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        )
        .doc(ids.scheduleId);
    installments = schedule
        .collection(FirestoreCollections.installments)
        .withConverter<Installment>(
          fromFirestore: Installment.fromFirestore,
          toFirestore: (i, _) => i.toFirestore(),
        );
    transactions = userDoc
        .collection(FirestoreCollections.transactions)
        .withConverter<domain.Transaction>(
          fromFirestore: domain.Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    transaction = transactions.doc(ids.transactionId);
    accounts = userDoc
        .collection(FirestoreCollections.accounts)
        .withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    account = movementAccountId == null
        ? null
        : accounts.doc(movementAccountId);
  }

  final DocumentReference<Map<String, dynamic>> userDoc;
  final DocumentReference<Loan> loan;
  late final DocumentReference<PaymentSchedule> schedule;
  late final CollectionReference<Installment> installments;
  late final CollectionReference<domain.Transaction> transactions;
  late final DocumentReference<domain.Transaction> transaction;
  late final CollectionReference<Account> accounts;
  late final DocumentReference<Account>? account;
}
