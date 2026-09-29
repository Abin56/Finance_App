import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/cash_flow/domain/cash_flow_period.dart';
import 'package:finance_app/features/cash_flow/domain/money_flow_line.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/credit_cards/domain/card_network.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for "Money Out must include credit-card expenses
/// regardless of the selected date-range preset" — the account type
/// (bank/card/cash/wallet/other) a transaction is posted against must never
/// change whether it counts toward Money Out; only the selected range
/// should. Also verifies `cashFlowThisMonthProvider` (Dashboard) and
/// `cashFlowForRangeProvider`/`cashFlowDateRangeProvider` (Cash Flow screen)
/// now share the exact same underlying calculation, so they can never
/// disagree about which account types are eligible.
void main() {
  late ProviderContainer container;

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
  });

  Future<String> createAccountOfType(
    ProviderContainer container,
    AccountType type, {
    String? name,
  }) async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: name ?? type.name,
      type: type,
      openingBalance: 10000,
      colorValue: 0xFF000000,
    );
    return account.id;
  }

  void setPreset(CashFlowPreset preset) {
    container.read(cashFlowDateRangeProvider.notifier).state =
        CashFlowPeriod.preset(preset);
  }

  void setCustomRange(DateTime start, DateTime end) {
    container.read(cashFlowDateRangeProvider.notifier).state =
        CashFlowPeriod.custom(DateRange(start, end));
  }

  group('Money Out includes credit-card expenses regardless of preset', () {
    test('Test 1 — This Month: bank + credit card both included', () async {
      final bankId = await createAccountOfType(container, AccountType.bank);
      final cardId = await createAccountOfType(container, AccountType.card);
      final transactions = container.read(transactionRepositoryProvider);
      final now = DateTime.now();

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: now,
        accountId: bankId,
        categoryId: 'food',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 700,
        dateTime: now,
        accountId: cardId,
        categoryId: 'restaurant',
      );
      await container.read(transactionsStreamProvider.future);

      setPreset(CashFlowPreset.thisMonth);
      expect(container.read(cashFlowForRangeProvider).moneyOut, 1200);
    });

    test(
      'Test 2 — This Week: same account-source logic as This Month',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);
        final now = DateTime.now();

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: now,
          accountId: bankId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: now,
          accountId: cardId,
          categoryId: 'restaurant',
        );
        await container.read(transactionsStreamProvider.future);

        setPreset(CashFlowPreset.thisWeek);
        expect(container.read(cashFlowForRangeProvider).moneyOut, 1200);
      },
    );

    test(
      'This Month and This Week produce identical account-type coverage for the same transactions',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);
        final now = DateTime.now();

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: now,
          accountId: bankId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: now,
          accountId: cardId,
          categoryId: 'restaurant',
        );
        await container.read(transactionsStreamProvider.future);

        setPreset(CashFlowPreset.thisMonth);
        final monthOut = container.read(cashFlowForRangeProvider).moneyOut;
        final monthLines = container.read(moneyOutLinesForRangeProvider);

        setPreset(CashFlowPreset.thisWeek);
        final weekOut = container.read(cashFlowForRangeProvider).moneyOut;
        final weekLines = container.read(moneyOutLinesForRangeProvider);

        expect(monthOut, weekOut);
        expect(monthLines.length, weekLines.length);
      },
    );

    test(
      'Test 3 — Custom range 01 Sep -> 30 Sep: both bank and credit-card expenses included',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: DateTime(2026, 9, 10),
          accountId: bankId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: DateTime(2026, 9, 15),
          accountId: cardId,
          categoryId: 'restaurant',
        );
        await container.read(transactionsStreamProvider.future);

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30, 23, 59, 59, 999),
        );
        expect(container.read(cashFlowForRangeProvider).moneyOut, 1200);
      },
    );

    test(
      'Test 4 — One-day range 01 Sep -> 01 Sep: bank 500 + credit card 700 = 1200',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: DateTime(2026, 9, 1, 9),
          accountId: bankId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: DateTime(2026, 9, 1, 20),
          accountId: cardId,
          categoryId: 'restaurant',
        );
        await container.read(transactionsStreamProvider.future);

        setCustomRange(
          DateTime(2026, 9, 1, 0, 0, 0),
          DateTime(2026, 9, 1, 23, 59, 59, 999),
        );
        expect(container.read(cashFlowForRangeProvider).moneyOut, 1200);
      },
    );

    test(
      'Test 5 — credit-card expense outside the range is excluded; only in-range portion counts',
      () async {
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 1000,
          dateTime: DateTime(2026, 8, 31, 12),
          accountId: cardId,
          categoryId: 'shopping',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: DateTime(2026, 9, 1, 12),
          accountId: cardId,
          categoryId: 'shopping',
        );
        await container.read(transactionsStreamProvider.future);

        setCustomRange(
          DateTime(2026, 9, 1, 0, 0, 0),
          DateTime(2026, 9, 1, 23, 59, 59, 999),
        );
        expect(
          container.read(cashFlowForRangeProvider).moneyOut,
          500,
          reason: 'Aug 31\'s ₹1000 must not leak in',
        );
      },
    );

    test(
      'Test 6 — bank-only expenses still work exactly as before (no regression)',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final transactions = container.read(transactionRepositoryProvider);
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: DateTime(2026, 9, 1),
          accountId: bankId,
          categoryId: 'food',
        );
        await container.read(transactionsStreamProvider.future);

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 1, 23, 59, 59, 999),
        );
        expect(container.read(cashFlowForRangeProvider).moneyOut, 500);
      },
    );

    test(
      'Test 7 — credit-card-only expenses: Money Out must not incorrectly show 0',
      () async {
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 900,
          dateTime: DateTime(2026, 9, 1),
          accountId: cardId,
          categoryId: 'shopping',
        );
        await container.read(transactionsStreamProvider.future);

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 1, 23, 59, 59, 999),
        );
        final result = container.read(cashFlowForRangeProvider);
        expect(result.moneyOut, 900);
        expect(result.moneyOut, isNot(0));
      },
    );

    test(
      'Test 8 — mixed sources: bank, credit card, cash, and wallet all included',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final cardId = await createAccountOfType(container, AccountType.card);
        final cashId = await createAccountOfType(container, AccountType.cash);
        final walletId = await createAccountOfType(
          container,
          AccountType.wallet,
        );
        final transactions = container.read(transactionRepositoryProvider);
        final day = DateTime(2026, 9, 1, 10);

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 100,
          dateTime: day,
          accountId: bankId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 200,
          dateTime: day,
          accountId: cardId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 300,
          dateTime: day,
          accountId: cashId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 400,
          dateTime: day,
          accountId: walletId,
          categoryId: 'food',
        );
        await container.read(transactionsStreamProvider.future);

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 1, 23, 59, 59, 999),
        );
        final lines = container.read(moneyOutLinesForRangeProvider);
        expect(lines, hasLength(4));
        expect(lines.fold(0.0, (s, l) => s + l.amount), 1000);
        expect(container.read(cashFlowForRangeProvider).moneyOut, 1000);
      },
    );

    // A purchase on a TRACKED credit card only raises card debt — cash leaves
    // when the card is paid (bank → card transfer). The same money is counted
    // exactly once: at payment, never at purchase too (mirrors Web).
    // `await provider.future` returns the already-resolved first snapshot, so
    // writes made after it are not seen yet. Let the fake Firestore snapshot
    // streams deliver before reading.
    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.read(transactionsStreamProvider.future);
      await container.read(creditCardsStreamProvider.future);
    }

    Future<String> createTrackedCard(String name) async {
      final cardAccountId = await createAccountOfType(
        container,
        AccountType.card,
        name: name,
      );
      await container
          .read(creditCardRepositoryProvider)
          .createCard(
            accountId: cardAccountId,
            statementDay: 1,
            paymentDueDay: 15,
            creditLimit: 50000,
            cardNetwork: CardNetwork.visa,
          );
      await settle();
      return cardAccountId;
    }

    test(
      'Test 9 — a tracked-card purchase is not cash out; paying the card from the bank is, once',
      () async {
        final cardAccountId = await createTrackedCard('Visa Card');
        final bankId = await createAccountOfType(container, AccountType.bank);
        final transactions = container.read(transactionRepositoryProvider);

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: DateTime(2026, 9, 1),
          accountId: cardAccountId,
          categoryId: 'restaurant',
        );
        await settle();

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30, 23, 59, 59, 999),
        );
        expect(
          container.read(cashFlowForRangeProvider).moneyOut,
          0,
          reason: 'the purchase only raised card debt — no cash left yet',
        );

        await transactions.createTransferPair(
          amount: 700,
          dateTime: DateTime(2026, 9, 20),
          sourceAccountId: bankId,
          destinationAccountId: cardAccountId,
          categoryId: 'transfer',
          description: 'Card bill',
        );
        await settle();

        final lines = container.read(moneyOutLinesForRangeProvider);
        expect(lines, hasLength(1));
        expect(lines.single.kind, MoneyFlowKind.creditCardPayment);
        expect(lines.single.amount, 700);
        expect(container.read(cashFlowForRangeProvider).moneyOut, 700);

        // An ordinary bank expense still counts as before.
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 300,
          dateTime: DateTime(2026, 9, 1),
          accountId: bankId,
          categoryId: 'food',
        );
        await settle();
        expect(container.read(cashFlowForRangeProvider).moneyOut, 1000);
      },
    );

    test(
      'Test 10 — income ₹7,000 + ₹1,000 tracked-card purchase leaves net cash flow at ₹7,000',
      () async {
        final cardAccountId = await createTrackedCard('OCTANE');
        final bankId = await createAccountOfType(container, AccountType.bank);
        final transactions = container.read(transactionRepositoryProvider);
        await transactions.createTransaction(
          type: TransactionType.income,
          amount: 7000,
          dateTime: DateTime(2026, 9, 1),
          accountId: bankId,
          categoryId: 'salary',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 1000,
          dateTime: DateTime(2026, 9, 1),
          accountId: cardAccountId,
          categoryId: 'bills',
        );
        await settle();

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30, 23, 59, 59, 999),
        );
        final result = container.read(cashFlowForRangeProvider);
        expect(result.moneyIn, 7000);
        expect(result.moneyOut, 0);
        expect(result.net, 7000);
      },
    );

    test(
      'Test 11 — a card refund is not Money In; a card-to-card transfer is not Money Out',
      () async {
        final cardA = await createTrackedCard('Card A');
        final cardB = await createTrackedCard('Card B');
        final transactions = container.read(transactionRepositoryProvider);
        await transactions.createTransaction(
          type: TransactionType.income,
          amount: 250,
          dateTime: DateTime(2026, 9, 2),
          accountId: cardA,
          categoryId: 'refund',
        );
        await transactions.createTransferPair(
          amount: 400,
          dateTime: DateTime(2026, 9, 3),
          sourceAccountId: cardA,
          destinationAccountId: cardB,
          categoryId: 'transfer',
        );
        await settle();

        setCustomRange(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30, 23, 59, 59, 999),
        );
        final result = container.read(cashFlowForRangeProvider);
        expect(result.moneyIn, 0);
        expect(result.moneyOut, 0);
      },
    );
  });

  group('Dashboard and Cash Flow screen This-Month figures never diverge', () {
    test(
      'cashFlowThisMonthProvider (Dashboard) and cashFlowForRangeProvider (Cash Flow screen, This Month preset) agree',
      () async {
        final bankId = await createAccountOfType(container, AccountType.bank);
        final cardId = await createAccountOfType(container, AccountType.card);
        final transactions = container.read(transactionRepositoryProvider);
        final now = DateTime.now();

        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 500,
          dateTime: now,
          accountId: bankId,
          categoryId: 'food',
        );
        await transactions.createTransaction(
          type: TransactionType.expense,
          amount: 700,
          dateTime: now,
          accountId: cardId,
          categoryId: 'restaurant',
        );
        await container.read(transactionsStreamProvider.future);

        setPreset(CashFlowPreset.thisMonth);
        final dashboard = container.read(cashFlowThisMonthProvider);
        final cashFlowScreen = container.read(cashFlowForRangeProvider);

        expect(dashboard.moneyOut, cashFlowScreen.moneyOut);
        expect(dashboard.moneyIn, cashFlowScreen.moneyIn);
        expect(dashboard.moneyOut, 1200);
      },
    );
  });

  group(
    'Money Out detail lines show the source account and match the summary',
    () {
      test(
        'detail lines carry the account label so bank vs credit card is distinguishable',
        () async {
          final bankId = await createAccountOfType(
            container,
            AccountType.bank,
            name: 'HDFC Bank',
          );
          final cardId = await createAccountOfType(
            container,
            AccountType.card,
            name: 'Visa Card',
          );
          final transactions = container.read(transactionRepositoryProvider);
          final day = DateTime(2026, 9, 1, 10);

          await transactions.createTransaction(
            type: TransactionType.expense,
            amount: 500,
            dateTime: day,
            accountId: bankId,
            categoryId: 'food',
            description: 'Food',
          );
          await transactions.createTransaction(
            type: TransactionType.expense,
            amount: 700,
            dateTime: day,
            accountId: cardId,
            categoryId: 'restaurant',
            description: 'Restaurant',
          );
          await container.read(transactionsStreamProvider.future);
          await container.read(accountsStreamProvider.future);

          setCustomRange(
            DateTime(2026, 9, 1),
            DateTime(2026, 9, 1, 23, 59, 59, 999),
          );
          final lines = container.read(moneyOutLinesForRangeProvider);

          final bankLine = lines.firstWhere((l) => l.title == 'Food');
          final cardLine = lines.firstWhere((l) => l.title == 'Restaurant');
          expect(bankLine.accountLabel, 'HDFC Bank');
          expect(cardLine.accountLabel, 'Visa Card');
          expect(bankLine.kind, MoneyFlowKind.expense);
          expect(cardLine.kind, MoneyFlowKind.expense);

          final summaryTotal = container
              .read(cashFlowForRangeProvider)
              .moneyOut;
          final linesTotal = lines.fold(0.0, (s, l) => s + l.amount);
          expect(linesTotal, summaryTotal);
        },
      );
    },
  );
}
