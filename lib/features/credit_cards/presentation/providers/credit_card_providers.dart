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
import '../../data/statement_payment_repository.dart';
import '../../data/statement_repository.dart';
import '../../domain/credit_card_profile.dart';
import '../../domain/statement.dart';
import '../../domain/statement_payment.dart';
import '../../domain/statement_period.dart';

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
  return CreditCardRepository(collection);
});

final creditCardsStreamProvider = StreamProvider<List<CreditCardProfile>>((ref) {
  return ref.watch(creditCardRepositoryProvider).watchAll();
});

/// Statement repository for a single card's subcollection, scoped by
/// [cardId] — mirrors `paymentRepositoryProvider` (Bills).
final statementRepositoryProvider = Provider.family<StatementRepository, String>((ref, cardId) {
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

final statementsStreamProvider = StreamProvider.family<List<Statement>, String>((ref, cardId) {
  return ref.watch(statementRepositoryProvider(cardId)).watchAll();
});

/// Statement-payment repository for a single statement's subcollection,
/// scoped by (cardId, statementId).
final statementPaymentRepositoryProvider =
    Provider.family<StatementPaymentRepository, ({String cardId, String statementId})>((ref, key) {
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

final statementPaymentsStreamProvider =
    StreamProvider.family<List<StatementPayment>, ({String cardId, String statementId})>((ref, key) {
  return ref.watch(statementPaymentRepositoryProvider(key)).watchAll();
});

/// Every transaction posted against [card]'s linked account — "purchases on
/// this card" per the 1:1 Account-IS-a-card design, reused by every
/// statement computation below instead of each re-filtering
/// [transactionsStreamProvider] independently.
final transactionsForCardProvider = Provider.family<List<Transaction>, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return const [];
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  return transactions.where((t) => t.accountId == card.accountId).toList();
});

/// The in-progress (not yet closed) cycle's live totals for [card] — never
/// written to Firestore, purely computed. The "lazy" half of statement
/// generation.
final currentStatementCycleProvider = Provider.family<Statement?, String>((ref, cardId) {
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
final materializeStatementProvider = FutureProvider.family<void, String>((ref, cardId) async {
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
final principalRestoredForCardProvider = Provider.family<double, String>((ref, cardId) {
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
/// [available] is [CreditCardProfile.creditLimit] minus [outstanding], plus
/// [principalRestoredForCardProvider] for any EMI converted from a purchase
/// on this card. Mirrors [Person.isCreditor]/[isDebtor] being derived
/// rather than persisted.
typedef CreditCardStanding = ({double outstanding, double available, double currentCycleSpend});

final creditCardStandingProvider = Provider.family<CreditCardStanding, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return (outstanding: 0, available: 0, currentCycleSpend: 0);

  final statements = ref.watch(statementsStreamProvider(cardId)).value ?? const [];
  final unpaidStatements = statements.fold(0.0, (sum, s) => sum + s.remainingAmount);
  final current = ref.watch(currentStatementCycleProvider(cardId));
  final currentCycleSpend = current?.totalAmount ?? 0;
  final outstanding = unpaidStatements + currentCycleSpend;
  final principalRestored = ref.watch(principalRestoredForCardProvider(cardId));

  return (
    outstanding: outstanding,
    available: (card.creditLimit - outstanding + principalRestored).clamp(0, card.creditLimit),
    currentCycleSpend: currentCycleSpend,
  );
});

/// The soonest not-fully-paid statement across every card, for the
/// Dashboard's "Next Due Date"/"Upcoming Due" stats.
final nextStatementDueProvider = Provider<Statement?>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  Statement? soonest;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
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
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  DateTime? soonest;
  for (final card in cards) {
    final period = StatementPeriodCalculator.currentCycleFor(card);
    if (soonest == null || period.periodEnd.isBefore(soonest)) soonest = period.periodEnd;
  }
  return soonest;
});

/// Sum of [CreditCardStanding.outstanding] across every card — the
/// Dashboard's "Current Credit Card Outstanding" stat.
final totalCreditCardOutstandingProvider = Provider<double>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  return cards.fold(0.0, (sum, c) => sum + ref.watch(creditCardStandingProvider(c.id)).outstanding);
});

/// Sum of [CreditCardStanding.available] across every card — the
/// Dashboard's "Credit Available" stat.
final totalCreditAvailableProvider = Provider<double>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  return cards.fold(0.0, (sum, c) => sum + ref.watch(creditCardStandingProvider(c.id)).available);
});

/// Sum of [CreditCardStanding.currentCycleSpend] across every card — the
/// Dashboard's "Current Cycle Spending" stat.
final totalCurrentCycleSpendProvider = Provider<double>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  return cards.fold(0.0, (sum, c) => sum + ref.watch(creditCardStandingProvider(c.id)).currentCycleSpend);
});

/// The [Account] a [CreditCardProfile] extends, if it still exists.
final accountForCardProvider = Provider.family<Account?, String>((ref, cardId) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final card = cards.where((c) => c.id == cardId).firstOrNull;
  if (card == null) return null;
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  return accounts.where((a) => a.id == card.accountId).firstOrNull;
});
