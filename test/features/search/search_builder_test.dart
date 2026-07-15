import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/expense_participant.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/search/domain/search_builder.dart';
import 'package:finance_app/features/search/domain/search_result.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 3, 10);

Transaction _txn({
  String id = 't1',
  String description = 'Coffee',
  String notes = '',
  double amount = 250,
  String categoryId = 'c1',
  String accountId = 'a1',
  DateTime? dateTime,
}) {
  return Transaction(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    dateTime: dateTime ?? _now,
    accountId: accountId,
    categoryId: categoryId,
    createdAt: _now,
    description: description,
    notes: notes,
  );
}

Category _category({String id = 'c1', String name = 'Food'}) =>
    Category(id: id, name: name, type: CategoryType.expense, iconKey: 'food', colorValue: 0, createdAt: _now);

Account _account({String id = 'a1', String name = 'HDFC', double currentBalance = 1000}) => Account(
      id: id,
      name: name,
      type: AccountType.bank,
      openingBalance: 0,
      currentBalance: currentBalance,
      colorValue: 0,
      createdAt: _now,
    );

Person _person({String id = 'p1', String name = 'Ravi', String? phone, double currentBalance = 0}) => Person(
      id: id,
      name: name,
      avatarColorValue: 0,
      openingBalance: 0,
      currentBalance: currentBalance,
      createdAt: _now,
      phone: phone,
    );

Expense _splitExpense({
  String id = 'e1',
  String description = 'Dinner',
  double totalAmount = 1200,
  String transactionId = 't-split',
}) {
  return Expense(
    id: id,
    description: description,
    totalAmount: totalAmount,
    date: _now,
    categoryId: 'c1',
    accountId: 'a1',
    transactionId: transactionId,
    splitType: SplitType.equal,
    participants: [
      ExpenseParticipant(name: 'Me', share: 600, isMe: true),
      ExpenseParticipant(name: 'Ravi', share: 600, personId: 'p1'),
    ],
    createdAt: _now,
  );
}

List<SearchResult> _build(
  String query, {
  List<Transaction> transactions = const [],
  List<Expense> expenses = const [],
  List<Person> people = const [],
  List<Account> accounts = const [],
  List<Category> categories = const [],
  List<Loan> loans = const [],
  List<Emi> emis = const [],
  List<Bill> bills = const [],
  List<CreditCardProfile> creditCards = const [],
}) {
  return SearchBuilder.build(
    query: query,
    transactions: transactions,
    expenses: expenses,
    people: people,
    accounts: accounts,
    categories: categories,
    loans: loans,
    emis: emis,
    bills: bills,
    creditCards: creditCards,
    accountNameById: {for (final a in accounts) a.id: a.name},
    categoryById: {for (final c in categories) c.id: c},
    personNameById: {for (final p in people) p.id: p.name},
  );
}

void main() {
  group('SearchQuery', () {
    test('matches text case-insensitively', () {
      expect(SearchQuery.parse('COFFEE').matchesText(['Morning coffee run']), isTrue);
      expect(SearchQuery.parse('tea').matchesText(['Morning coffee run']), isFalse);
    });

    test('ignores null fields', () {
      expect(SearchQuery.parse('x').matchesText([null, 'nope']), isFalse);
    });

    test('matches an amount across its whole-rupee and decimal renderings', () {
      final q = SearchQuery.parse('500');
      expect(q.matchesAmount(500), isTrue);
      // Substring semantics: a partial amount still finds the record.
      expect(q.matchesAmount(1500), isTrue);
      expect(q.matchesAmount(42), isFalse);
    });

    test('strips currency punctuation before matching an amount', () {
      expect(SearchQuery.parse('₹1,500').matchesAmount(1500), isTrue);
    });

    test('an empty query matches nothing', () {
      final q = SearchQuery.parse('   ');
      expect(q.isEmpty, isTrue);
      expect(q.matchesText(['anything']), isFalse);
      expect(q.matchesAmount(1), isFalse);
    });
  });

  group('SearchBuilder', () {
    test('returns nothing for a blank query rather than the whole database', () {
      expect(_build('', transactions: [_txn()], categories: [_category()]), isEmpty);
      expect(_build('   ', transactions: [_txn()], categories: [_category()]), isEmpty);
    });

    test('finds a transaction by description', () {
      final results = _build('coffee', transactions: [_txn()], categories: [_category()], accounts: [_account()]);
      expect(results, hasLength(1));
      expect(results.single.title, 'Coffee');
      expect(results.single.group, SearchResultGroup.transactions);
      expect(results.single.routePath, '/transactions/t1');
    });

    test('finds a transaction by its category name', () {
      final results = _build('food', transactions: [_txn()], categories: [_category()], accounts: [_account()]);
      // The Food category itself also matches, so scope to the group.
      final txn = results.singleWhere((r) => r.group == SearchResultGroup.transactions);
      expect(txn.title, 'Coffee');
      expect(txn.subtitle, 'Food · HDFC');
    });

    test('finds a transaction by its account name', () {
      final results = _build('hdfc', transactions: [_txn()], categories: [_category()], accounts: [_account()]);
      // The account itself also matches its own name, so scope to the group.
      final txns = results.where((r) => r.group == SearchResultGroup.transactions);
      expect(txns.single.title, 'Coffee');
    });

    test('finds a transaction by amount', () {
      final results = _build('250', transactions: [_txn()], categories: [_category()], accounts: [_account()]);
      expect(results.where((r) => r.group == SearchResultGroup.transactions), hasLength(1));
    });

    test('finds a transaction by notes', () {
      final results = _build('refund', transactions: [_txn(notes: 'pending refund')], categories: [_category()]);
      expect(results, hasLength(1));
    });

    test('excludes soft-deleted records', () {
      final deleted = _txn()..markDeleted();
      expect(_build('coffee', transactions: [deleted], categories: [_category()]), isEmpty);
    });

    test('lists a split expense once, not also as its balance transaction', () {
      // A split expense owns a transaction for its account-balance effect;
      // both would otherwise match "dinner" and show as duplicate rows.
      final expense = _splitExpense();
      final results = _build(
        'dinner',
        transactions: [_txn(id: 't-split', description: 'Dinner')],
        expenses: [expense],
        categories: [_category()],
        accounts: [_account()],
      );
      expect(results, hasLength(1));
      expect(results.single.group, SearchResultGroup.splitExpenses);
      // Deep-links to the underlying transaction's detail screen.
      expect(results.single.routePath, '/transactions/t-split');
    });

    test('finds a split expense by a participant name', () {
      final results = _build('ravi', expenses: [_splitExpense()], categories: [_category()], accounts: [_account()]);
      final split = results.where((r) => r.group == SearchResultGroup.splitExpenses);
      expect(split.single.title, 'Dinner');
      expect(split.single.subtitle, contains('Split with 1 person'));
    });

    test('finds a person by name and by phone', () {
      final person = _person(phone: '9876543210');
      expect(_build('ravi', people: [person]).single.group, SearchResultGroup.people);
      expect(_build('98765', people: [person]).single.title, 'Ravi');
    });

    test('groups results in enum order', () {
      // "a" matches across several features at once.
      final results = _build(
        'a',
        transactions: [_txn(description: 'Apple')],
        people: [_person(name: 'Ravi')],
        accounts: [_account(name: 'Axis')],
        categories: [_category(name: 'Travel')],
      );
      final groups = results.map((r) => r.group).toList();
      final sorted = [...groups]..sort((x, y) => x.index.compareTo(y.index));
      expect(groups, sorted);
    });

    test('orders newest first within a group', () {
      final results = _build(
        'coffee',
        transactions: [
          _txn(id: 'old', dateTime: DateTime(2026, 1, 1)),
          _txn(id: 'new', dateTime: DateTime(2026, 3, 1)),
        ],
        categories: [_category()],
      );
      expect(results.map((r) => r.id), ['txn-new', 'txn-old']);
    });

    test('finds a bill by name and deep-links to it', () {
      final bill = Bill(
        id: 'b1',
        name: 'Electricity',
        amount: 1800,
        dueDate: _now,
        recurrence: BillRecurrence.monthly,
        createdAt: _now,
      );
      final results = _build('electric', bills: [bill]);
      expect(results.single.group, SearchResultGroup.bills);
      expect(results.single.routePath, '/bills/b1');
    });

    test('finds a loan by the person it belongs to', () {
      final loan = Loan(
        id: 'l1',
        personId: 'p1',
        loanAmount: 50000,
        loanDate: _now,
        repaymentType: LoanRepaymentType.oneTime,
        scheduleId: 's1',
        createdAt: _now,
      );
      final results = _build('ravi', people: [_person()], loans: [loan]);
      final loanResults = results.where((r) => r.group == SearchResultGroup.loans);
      expect(loanResults.single.routePath, '/loans/l1');
      expect(loanResults.single.title, 'Ravi');
    });

    test('finds an EMI by lender name', () {
      final emi = Emi(
        id: 'm1',
        name: 'Bike loan',
        principalAmount: 80000,
        startDate: _now,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        endDate: DateTime(2027, 3, 10),
        scheduleId: 's2',
        createdAt: _now,
        lenderName: 'Bajaj',
      );
      final results = _build('bajaj', emis: [emi]);
      expect(results.single.title, 'Bike loan');
      expect(results.single.routePath, '/emis/m1');
    });

    test('finds a credit card by its last four digits, named by its account', () {
      final card = CreditCardProfile(
        id: 'cc1',
        accountId: 'a1',
        statementDay: 5,
        paymentDueDay: 25,
        creditLimit: 100000,
        createdAt: _now,
        lastFourDigits: '4321',
      );
      final results = _build('4321', creditCards: [card], accounts: [_account()]);
      final cards = results.where((r) => r.group == SearchResultGroup.creditCards);
      expect(cards.single.title, 'HDFC');
      expect(cards.single.routePath, '/creditCards/cc1');
    });

    test('finds an account and a category by name', () {
      expect(_build('hdfc', accounts: [_account()]).single.group, SearchResultGroup.accounts);
      expect(_build('food', categories: [_category()]).single.group, SearchResultGroup.categories);
    });
  });
}
