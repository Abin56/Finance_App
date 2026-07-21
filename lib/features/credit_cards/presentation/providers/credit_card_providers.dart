import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/credit_card_repository.dart';
import '../../data/shared_credit_limit_repository.dart';
import '../../data/statement_payment_repository.dart';
import '../../data/statement_repository.dart';
import '../../domain/credit_card_profile.dart';
import '../../domain/shared_credit_limit.dart';
import '../../domain/statement.dart';
import '../../domain/statement_payment.dart';
import '../../domain/statement_period.dart';

final sharedCreditLimitRepositoryProvider = Provider<SharedCreditLimitRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.sharedCreditLimits)
      .withConverter<SharedCreditLimit>(
        fromFirestore: SharedCreditLimit.fromFirestore,
        toFirestore: (sharedLimit, _) => sharedLimit.toFirestore(),
      );
  return SharedCreditLimitRepository(collection);
});

final sharedCreditLimitsStreamProvider = StreamProvider<List<SharedCreditLimit>>((ref) {
  return ref.watch(sharedCreditLimitRepositoryProvider).watchAll();
});

final creditCardRepositoryProvider = Provider<CreditCardRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.creditCards)
      .withConverter<CreditCardProfile>(
        fromFirestore: CreditCardProfile.fromFirestore,
        toFirestore: (card, _) => card.toFirestore(),
      );
  return CreditCardRepository(collection, sharedCreditLimitRepository: ref.watch(sharedCreditLimitRepositoryProvider));
});

final creditCardsStreamProvider = StreamProvider<List<CreditCardProfile>>((ref) {
  return ref.watch(creditCardRepositoryProvider).watchAll();
});

/// [creditCardsStreamProvider] filtered to cards whose linked [Account]
/// hasn't been deleted. [CreditCardProfile] has no delete action of its own
/// anywhere in this module — the only way a user removes a card today is
/// deleting its linked Account from the Accounts screen, which soft-deletes
/// only the Account (accounts has no knowledge of credit_cards, so it can't
/// cascade the delete to the card). Every screen/aggregation that shows or
/// sums cards should watch this instead of the raw stream above, so a
/// card's outstanding balance stops counting — and the card itself stops
/// appearing — the moment its account is trashed, and both reappear
/// correctly if the account is restored.
final activeCreditCardsProvider = Provider<List<CreditCardProfile>>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final accountIds = (ref.watch(accountsStreamProvider).value ?? const []).map((a) => a.id).toSet();
  return cards.where((c) => accountIds.contains(c.accountId)).toList();
});

/// Every active card drawing from [sharedLimitId] — the sibling cards of a
/// shared credit limit, e.g. a Visa and RuPay variant issued under the same
/// facility.
final cardsUnderSharedLimitProvider = Provider.autoDispose.family<List<CreditCardProfile>, String>((
  ref,
  sharedLimitId,
) {
  final cards = ref.watch(activeCreditCardsProvider);
  return cards.where((c) => c.sharedLimitId == sharedLimitId).toList();
});

/// The [SharedCreditLimit] a card draws from, or null if it's standalone.
final sharedCreditLimitForCardProvider = Provider.autoDispose.family<SharedCreditLimit?, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card?.sharedLimitId == null) return null;
  final sharedLimits = ref.watch(sharedCreditLimitsStreamProvider).value ?? const [];
  return sharedLimits.where((g) => g.id == card!.sharedLimitId).firstOrNull;
});

/// Statement repository for a single card's subcollection, scoped by
/// [cardId] — mirrors `paymentRepositoryProvider` (Bills).
final statementRepositoryProvider = Provider.autoDispose.family<StatementRepository, String>((ref, cardId) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.creditCards)
      .doc(cardId)
      .collection(FirestoreCollections.statements)
      .withConverter<Statement>(
        fromFirestore: Statement.fromFirestore,
        toFirestore: (statement, _) => statement.toFirestore(),
      );
  return StatementRepository(collection);
});

final statementsStreamProvider = StreamProvider.autoDispose.family<List<Statement>, String>((ref, cardId) {
  return ref.watch(statementRepositoryProvider(cardId)).watchAll();
});

/// [statementsStreamProvider] with every statement's `totalAmount`/
/// `minimumDue` corrected against what its period's transactions currently
/// sum to, instead of the value stored at materialization time — a
/// transaction dated inside an already-closed statement can still be
/// deleted, edited, or restored afterward, and the stored document is never
/// itself rewritten for that (see the class doc on [Statement]). Every
/// screen/provider that shows or sums a *closed* statement's total (as
/// opposed to [currentStatementCycleProvider], which is already always
/// live) must watch this instead of [statementsStreamProvider] directly.
final statementsWithLiveTotalsProvider = Provider.autoDispose.family<List<Statement>, String>((ref, cardId) {
  final statements = ref.watch(statementsStreamProvider(cardId)).value ?? const [];
  if (statements.isEmpty) return statements;

  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return statements;

  final cardTransactions = ref.watch(transactionsForCardProvider(cardId));
  final repository = ref.watch(statementRepositoryProvider(cardId));
  return statements.map((statement) {
    final period = StatementPeriod(
      periodStart: statement.periodStart,
      periodEnd: statement.periodEnd,
      dueDate: statement.dueDate,
    );
    final liveTotal = repository.totalFor(cardTransactions, period);
    final liveMinimumDue = card.minimumDuePercent == null ? null : liveTotal * card.minimumDuePercent! / 100;
    return statement.withLiveTotal(liveTotal, liveMinimumDue);
  }).toList();
});

/// Statement-payment repository for a single statement's subcollection,
/// scoped by (cardId, statementId).
final statementPaymentRepositoryProvider = Provider.autoDispose
    .family<StatementPaymentRepository, ({String cardId, String statementId})>((ref, key) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.creditCards)
      .doc(key.cardId)
      .collection(FirestoreCollections.statements)
      .doc(key.statementId)
      .collection(FirestoreCollections.statementPayments)
      .withConverter<StatementPayment>(
        fromFirestore: StatementPayment.fromFirestore,
        toFirestore: (payment, _) => payment.toFirestore(),
      );
  return StatementPaymentRepository(
    collection,
    ref.watch(statementRepositoryProvider(key.cardId)),
    ref.watch(transactionRepositoryProvider),
  );
});

final statementPaymentsStreamProvider = StreamProvider.autoDispose
    .family<List<StatementPayment>, ({String cardId, String statementId})>((ref, key) {
  return ref.watch(statementPaymentRepositoryProvider(key)).watchAll();
});

/// Every transaction posted against [card]'s linked account — "purchases on
/// this card" per the 1:1 Account-IS-a-card design, reused by every
/// statement computation below instead of each re-filtering
/// [transactionsStreamProvider] independently.
final transactionsForCardProvider = Provider.autoDispose.family<List<Transaction>, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return const [];
  final transactions = ref.watch(calculableTransactionsProvider);
  return transactions.where((t) => t.accountId == card.accountId).toList();
});

/// The in-progress (not yet closed) cycle's live totals for [card] — never
/// written to Firestore, purely computed. The "lazy" half of statement
/// generation.
final currentStatementCycleProvider = Provider.autoDispose.family<Statement?, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return null;
  final cardTransactions = ref.watch(transactionsForCardProvider(cardId));
  return ref.watch(statementRepositoryProvider(cardId)).currentCycleFor(card, cardTransactions);
});

/// Triggers `StatementRepository.materializeIfDue` as a side effect
/// whenever a card's screen is opened (i.e. whenever this provider is
/// watched) — the "materialize-on-read" half of statement generation.
/// Screens watch [statementsStreamProvider] for the actual list; this
/// provider's return value only matters for surfacing an error, if any.
final materializeStatementProvider = FutureProvider.autoDispose.family<void, String>((ref, cardId) async {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return;
  final cardTransactions = ref.watch(transactionsForCardProvider(cardId));
  final existing = ref.watch(statementsStreamProvider(cardId)).value ?? const [];
  await ref.watch(statementRepositoryProvider(cardId)).materializeIfDue(card, cardTransactions, existing);
});

/// Sum of principal paid so far across every EMI linked to [cardId] — the
/// amount a bank would restore to available credit as a converted purchase
/// is paid down. Uses each payment's `EmiPaymentBreakdown.principalPaid`
/// when present (the real, explicit split entered at payment time); falls
/// back to the installment's theoretical `principalPortion` share of the
/// payment for payments recorded with no breakdown (before this feature
/// existed, or via the multi-payment sheet) — for a non-interest EMI
/// (`principalPortion == null`), the whole payment counts as principal,
/// which is correct since there's no interest to separate out. Purely
/// derived, like [creditCardStandingProvider] itself — nothing is written
/// back to the card or the EMI when this changes.
final principalRestoredForCardProvider = Provider.autoDispose.family<double, String>((ref, cardId) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  final linked = emis.where((e) => e.linkedCreditCardId == cardId);

  var restored = 0.0;
  for (final emi in linked) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    final breakdowns = ref.watch(emiPaymentBreakdownsStreamProvider(emi.id)).value ?? const [];
    final breakdownByPaymentId = {for (final b in breakdowns) b.paymentId: b};

    for (final installment in installments) {
      final payments = ref
              .watch(installmentPaymentsStreamProvider((scheduleId: emi.scheduleId, installmentId: installment.id)))
              .value ??
          const [];
      for (final payment in payments) {
        final breakdown = breakdownByPaymentId[payment.id];
        if (breakdown != null) {
          restored += breakdown.principalPaid;
          continue;
        }
        final principalPortion = installment.principalPortion;
        if (principalPortion == null || installment.amountDue == 0) {
          restored += payment.amount;
        } else {
          restored += payment.amount * (principalPortion / installment.amountDue);
        }
      }
    }
  }
  return restored;
});

/// A card's computed running figures — [outstanding] is every unpaid
/// statement's remaining amount plus the current cycle's spend-to-date;
/// [available] is the credit limit minus [outstanding], plus any principal
/// restored by EMIs converted from card purchases. Mirrors
/// [Person.isCreditor]/[isDebtor] being derived rather than persisted.
typedef CreditCardStanding = ({double outstanding, double available, double currentCycleSpend});

/// This one card's own (unpaidStatements, currentCycleSpend) — the pieces
/// [creditCardStandingProvider] and [sharedCreditLimitStandingProvider] both
/// need, factored out so a shared-limit card's siblings can be summed
/// without duplicating the "already materialized" same-cycle-day guard
/// below.
({double outstanding, double currentCycleSpend}) _cardOwnStanding(Ref ref, String cardId) {
  final statements = ref.watch(statementsWithLiveTotalsProvider(cardId));
  final unpaidStatements = statements.fold(0.0, (sum, s) => sum + s.remainingAmount);
  final current = ref.watch(currentStatementCycleProvider(cardId));
  // On the exact day a cycle closes, `currentCycleFor` (which backs
  // [current]) hasn't rolled forward to the next cycle yet — it still
  // reports the just-closed cycle's live total, the same cycle a
  // `Statement` may already have been materialized for (see
  // `StatementPeriodCalculator.mostRecentClosedCycleFor`, which treats
  // that same day as closed). Excluding `current` once a matching
  // Statement exists avoids double-counting that one cycle's spend in
  // both `unpaidStatements` and `currentCycleSpend` for that single day.
  final alreadyMaterialized = current != null &&
      statements.any(
        (s) => s.periodStart.isAtSameMomentAs(current.periodStart) && s.periodEnd.isAtSameMomentAs(current.periodEnd),
      );
  final currentCycleSpend = alreadyMaterialized ? 0.0 : (current?.totalAmount ?? 0);
  return (outstanding: unpaidStatements + currentCycleSpend, currentCycleSpend: currentCycleSpend);
}

/// The pooled standing across every card drawing from [sharedLimitId] —
/// sums each sibling's own outstanding/spend/principal-restored against the
/// facility's single [SharedCreditLimit.creditLimit], so a purchase on any
/// member card (e.g. the Visa variant) immediately reduces the availability
/// every sibling (e.g. the RuPay variant) also sees.
final sharedCreditLimitStandingProvider = Provider.autoDispose.family<CreditCardStanding, String>((
  ref,
  sharedLimitId,
) {
  final sharedLimits = ref.watch(sharedCreditLimitsStreamProvider).value ?? const [];
  final sharedLimit = sharedLimits.where((g) => g.id == sharedLimitId).firstOrNull;
  if (sharedLimit == null) return (outstanding: 0, available: 0, currentCycleSpend: 0);

  final memberCards = ref.watch(cardsUnderSharedLimitProvider(sharedLimitId));
  var totalOutstanding = 0.0;
  var totalCurrentCycleSpend = 0.0;
  var totalPrincipalRestored = 0.0;
  for (final card in memberCards) {
    final own = _cardOwnStanding(ref, card.id);
    totalOutstanding += own.outstanding;
    totalCurrentCycleSpend += own.currentCycleSpend;
    totalPrincipalRestored += ref.watch(principalRestoredForCardProvider(card.id));
  }

  return (
    outstanding: totalOutstanding,
    available: (sharedLimit.creditLimit - totalOutstanding + totalPrincipalRestored).clamp(0, sharedLimit.creditLimit),
    currentCycleSpend: totalCurrentCycleSpend,
  );
});

/// A single card's standing — delegates to [sharedCreditLimitStandingProvider]
/// when the card draws from a shared credit limit (every sibling then
/// reports the identical facility-wide figures), otherwise computes today's
/// standalone standing off this card's own [CreditCardProfile.creditLimit].
final creditCardStandingProvider = Provider.autoDispose.family<CreditCardStanding, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return (outstanding: 0, available: 0, currentCycleSpend: 0);

  if (card.sharedLimitId != null) {
    return ref.watch(sharedCreditLimitStandingProvider(card.sharedLimitId!));
  }

  final own = _cardOwnStanding(ref, cardId);
  final principalRestored = ref.watch(principalRestoredForCardProvider(cardId));

  return (
    outstanding: own.outstanding,
    available: (card.creditLimit - own.outstanding + principalRestored).clamp(0, card.creditLimit),
    currentCycleSpend: own.currentCycleSpend,
  );
});

/// The soonest not-fully-paid statement across every card, for the
/// Dashboard's "Next Due Date"/"Upcoming Due" stats.
final nextStatementDueProvider = Provider<Statement?>((ref) {
  final cards = ref.watch(activeCreditCardsProvider);
  Statement? soonest;
  for (final card in cards) {
    final statements = ref.watch(statementsWithLiveTotalsProvider(card.id));
    for (final statement in statements) {
      if (statement.remainingAmount <= 0) continue;
      if (soonest == null || statement.dueDate.isBefore(soonest.dueDate)) soonest = statement;
    }
  }
  return soonest;
});

/// The soonest upcoming statement date (current cycle's `periodEnd`)
/// across every card, for the Dashboard's "Next Statement Date" stat.
final nextStatementDateProvider = Provider<DateTime?>((ref) {
  final cards = ref.watch(activeCreditCardsProvider);
  DateTime? soonest;
  for (final card in cards) {
    final period = StatementPeriodCalculator.currentCycleFor(card);
    if (soonest == null || period.periodEnd.isBefore(soonest)) soonest = period.periodEnd;
  }
  return soonest;
});

/// Sums [selector] over every card, counting a shared credit limit's
/// standing exactly once no matter how many member cards it has — the
/// dashboard totals below all reduce to this so a shared Visa/RuPay pair
/// isn't double-counted.
double _sumStandingAcrossCards(Ref ref, double Function(CreditCardStanding) selector) {
  final cards = ref.watch(activeCreditCardsProvider);
  final countedSharedLimits = <String>{};
  var sum = 0.0;
  for (final card in cards) {
    if (card.sharedLimitId != null) {
      if (!countedSharedLimits.add(card.sharedLimitId!)) continue;
      sum += selector(ref.watch(sharedCreditLimitStandingProvider(card.sharedLimitId!)));
    } else {
      sum += selector(ref.watch(creditCardStandingProvider(card.id)));
    }
  }
  return sum;
}

/// Sum of [CreditCardStanding.outstanding] across every card/facility — the
/// Dashboard's "Current Credit Card Outstanding" stat.
final totalCreditCardOutstandingProvider = Provider<double>((ref) {
  return _sumStandingAcrossCards(ref, (s) => s.outstanding);
});

/// Sum of [CreditCardStanding.available] across every card/facility — the
/// Dashboard's "Credit Available" stat.
final totalCreditAvailableProvider = Provider<double>((ref) {
  return _sumStandingAcrossCards(ref, (s) => s.available);
});

/// Sum of [CreditCardStanding.currentCycleSpend] across every card/facility —
/// the Dashboard's "Current Cycle Spending" stat.
final totalCurrentCycleSpendProvider = Provider<double>((ref) {
  return _sumStandingAcrossCards(ref, (s) => s.currentCycleSpend);
});

/// Sum of every card/facility's credit limit, counting a shared credit
/// limit's [SharedCreditLimit.creditLimit] exactly once no matter how many
/// member cards it has — mirrors [_sumStandingAcrossCards]'s dedup so
/// figures like "Credit Utilization %" don't double-count a shared
/// Visa/RuPay pair's limit in the denominator.
final totalCreditLimitProvider = Provider<double>((ref) {
  final cards = ref.watch(activeCreditCardsProvider);
  final sharedLimits = ref.watch(sharedCreditLimitsStreamProvider).value ?? const [];
  final sharedLimitById = {for (final g in sharedLimits) g.id: g.creditLimit};
  final countedSharedLimits = <String>{};
  var sum = 0.0;
  for (final card in cards) {
    if (card.sharedLimitId != null) {
      if (!countedSharedLimits.add(card.sharedLimitId!)) continue;
      sum += sharedLimitById[card.sharedLimitId!] ?? 0;
    } else {
      sum += card.creditLimit;
    }
  }
  return sum;
});

/// The [Account] a [CreditCardProfile] extends, if it still exists.
final accountForCardProvider = Provider.autoDispose.family<Account?, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return null;
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  return accounts.where((a) => a.id == card.accountId).firstOrNull;
});
