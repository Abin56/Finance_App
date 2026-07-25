import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_anchor.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `statementCycleViewProvider`/`creditCardStandingProvider`
/// against a real `ProviderContainer` (the confirmed gap: previously only
/// `StatementRepository`'s own unit tests exercised
/// `materializeIfDue`/`currentCycleFor` in isolation, and
/// `credit_card_standing_test.dart` only tested the `available` formula as a
/// free function, never the real provider).
///
/// `statementDay` is fixed at 1; `closedPeriod`/`currentPeriod` are derived
/// from the exact same `CycleAnchor` the providers use internally
/// (`anchorDay: statementDay`), rather than hand-approximated, so this test
/// is correct regardless of what day it happens to run on.
void main() {
  late ProviderContainer container;
  const statementDay = 1;
  late DateTime closedPeriodStart;
  late DateTime closedPeriodEnd;
  late DateTime currentPeriodStart;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    const anchor = CycleAnchor(anchorDay: statementDay);
    final currentPeriod = anchor.currentCycleFor();
    final previousPeriod = anchor.previousCycleFor();
    currentPeriodStart = currentPeriod.start;
    closedPeriodStart = previousPeriod.start;
    closedPeriodEnd = previousPeriod.end;
  });

  Future<({String cardId, String accountId})> createCardWithAccount() async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: 'Test Card',
      type: AccountType.card,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );

    final cards = container.read(creditCardRepositoryProvider);
    final card = await cards.createCard(
      accountId: account.id,
      statementDay: statementDay,
      paymentDueDay: statementDay,
      creditLimit: 100000,
    );

    await container.read(accountsStreamProvider.future);
    await container.read(creditCardsStreamProvider.future);
    return (cardId: card.id, accountId: account.id);
  }

  /// Materializes a closed statement AND posts a matching real transaction
  /// dated inside that same closed period — `statementsWithLiveTotalsProvider`
  /// re-derives `totalAmount` from live transactions on every read (see its
  /// doc comment), so a statement with no backing transaction would have its
  /// stored [totalAmount] corrected down to 0, making every unpaid statement
  /// look settled. The transaction is what keeps [totalAmount] real here.
  Future<void> addClosedStatement(
    String cardId,
    String accountId, {
    required double totalAmount,
    required double amountPaid,
  }) async {
    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: totalAmount,
      dateTime: closedPeriodStart,
      accountId: accountId,
      categoryId: 'cat1',
    );
    await container.read(transactionsStreamProvider.future);

    final statements = container.read(statementRepositoryProvider(cardId));
    await statements.add(
      'stmt-$cardId',
      Statement(
        id: 'stmt-$cardId',
        cardId: cardId,
        periodStart: closedPeriodStart,
        periodEnd: closedPeriodEnd,
        generatedDate: closedPeriodEnd,
        dueDate: closedPeriodEnd.add(const Duration(days: 5)),
        totalAmount: totalAmount,
        amountPaid: amountPaid,
        createdAt: closedPeriodEnd,
      ),
    );
    await container.read(statementsStreamProvider(cardId).future);
  }

  test('an unpaid closed statement from before the current cycle carries forward as pending', () async {
    final (:cardId, :accountId) = await createCardWithAccount();
    await addClosedStatement(cardId, accountId, totalAmount: 1000, amountPaid: 0);

    final view = container.read(statementCycleViewProvider(cardId));

    expect(view.previousCyclePending.map((s) => s.id), ['stmt-$cardId']);
  });

  test('a fully paid closed statement from before the current cycle does not carry forward', () async {
    final (:cardId, :accountId) = await createCardWithAccount();
    await addClosedStatement(cardId, accountId, totalAmount: 1000, amountPaid: 1000);

    final view = container.read(statementCycleViewProvider(cardId));

    expect(view.previousCyclePending, isEmpty);
  });

  test('a partially paid closed statement still carries forward as pending', () async {
    final (:cardId, :accountId) = await createCardWithAccount();
    await addClosedStatement(cardId, accountId, totalAmount: 1000, amountPaid: 400);

    final view = container.read(statementCycleViewProvider(cardId));

    expect(view.previousCyclePending.map((s) => s.id), ['stmt-$cardId']);
  });

  test('current reflects the live in-progress cycle, not a materialized statement', () async {
    final (:cardId, :accountId) = await createCardWithAccount();

    final view = container.read(statementCycleViewProvider(cardId));

    expect(view.current, isNotNull);
    expect(view.current!.id, 'current');
    expect(view.current!.periodStart, currentPeriodStart);
  });

  test(
    'creditCardStandingProvider.outstanding does not double count a statement materialized for '
    'the exact cycle currentCycleFor still reports as in-progress',
    () async {
      final (:cardId, :accountId) = await createCardWithAccount();
      // A statement materialized for the closed previous cycle must not
      // also be counted again via currentCycleSpend for the (separate,
      // still-open) current cycle.
      await addClosedStatement(cardId, accountId, totalAmount: 1000, amountPaid: 0);

      final standing = container.read(creditCardStandingProvider(cardId));

      // Outstanding must count the unpaid statement's remaining amount
      // exactly once, not also add it again via currentCycleSpend.
      expect(standing.outstanding, 1000);
    },
  );

  test('outstanding sums remaining (not total) amounts for partially paid statements', () async {
    final (:cardId, :accountId) = await createCardWithAccount();
    await addClosedStatement(cardId, accountId, totalAmount: 1000, amountPaid: 400);

    final standing = container.read(creditCardStandingProvider(cardId));

    expect(standing.outstanding, 600);
  });

  test('a transaction posted in the current cycle counts toward currentCycleSpend and outstanding', () async {
    final (:cardId, :accountId) = await createCardWithAccount();
    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 250,
      dateTime: DateTime.now(),
      accountId: accountId,
      categoryId: 'cat1',
    );
    await container.read(transactionsStreamProvider.future);

    final standing = container.read(creditCardStandingProvider(cardId));

    expect(standing.currentCycleSpend, 250);
    expect(standing.outstanding, 250);
  });
}
