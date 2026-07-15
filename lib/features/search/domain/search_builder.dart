import 'package:flutter/material.dart';

import '../../../core/router/app_routes.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/account_type.dart';
import '../../bills/domain/bill.dart';
import '../../bills/domain/bill_recurrence.dart';
import '../../categories/domain/category.dart';
import '../../categories/domain/category_icons.dart';
import '../../credit_cards/domain/card_network.dart';
import '../../credit_cards/domain/credit_card_profile.dart';
import '../../emi/domain/emi.dart';
import '../../expense/domain/expense.dart';
import '../../lending/domain/loan.dart';
import '../../people/domain/person.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_type.dart';
import 'search_result.dart';

/// A parsed user query, so every entity's matcher agrees on what "matches"
/// means instead of each re-implementing case folding and number parsing.
///
/// A result matches when the query hits *any* of its text fields, or its
/// amount. Both are substring matches: typing `50` finds ₹50 and ₹1,500,
/// which is the forgiving behaviour a search box wants — Search is for
/// finding things, not for exact filtering (History's own filters do that).
class SearchQuery {
  SearchQuery._(this.text, this.digits);

  factory SearchQuery.parse(String raw) {
    final text = raw.trim().toLowerCase();
    // Strip anything that isn't part of a number so "₹1,500" / "1,500"
    // both reduce to the digits an amount would be stored as.
    final digits = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return SearchQuery._(text, digits.isEmpty ? null : digits);
  }

  final String text;

  /// The numeric portion of the query, if it has one.
  final String? digits;

  bool get isEmpty => text.isEmpty;

  bool matchesText(Iterable<String?> fields) {
    if (isEmpty) return false;
    for (final field in fields) {
      if (field != null && field.toLowerCase().contains(text)) return true;
    }
    return false;
  }

  /// Matches [value] against the query's numeric part, comparing against
  /// both the whole-rupee and two-decimal renderings so `500`, `500.0` and
  /// `500.00` all find the same record.
  bool matchesAmount(double? value) {
    final digits = this.digits;
    if (digits == null || value == null) return false;
    return value.toStringAsFixed(0).contains(digits) || value.toStringAsFixed(2).contains(digits);
  }

  /// Convenience for the common "text fields OR amount" rule.
  bool matches(Iterable<String?> fields, {double? amount}) =>
      matchesText(fields) || matchesAmount(amount);
}

/// Folds every searchable feature into one grouped [SearchResult] list —
/// the single place global Search gets its data. Pure: takes already-loaded
/// collections and already-resolved name lookups (the provider layer owns
/// the I/O, exactly as `HistoryBuilder` does), invents no business logic,
/// and derives no balances or statuses. It only matches and labels.
abstract class SearchBuilder {
  SearchBuilder._();

  /// Results across every feature, grouped by [SearchResultGroup] in enum
  /// order and newest-first within each group. Returns empty for a blank
  /// query — Search shows its prompt state rather than the whole database.
  ///
  /// The `*NameById` maps let a transaction be found by its category or
  /// account name ("Food", "HDFC") without this builder re-resolving those
  /// relationships itself.
  static List<SearchResult> build({
    required String query,
    required List<Transaction> transactions,
    required List<Expense> expenses,
    required List<Person> people,
    required List<Account> accounts,
    required List<Category> categories,
    required List<Loan> loans,
    required List<Emi> emis,
    required List<Bill> bills,
    required List<CreditCardProfile> creditCards,
    Map<String, String> accountNameById = const {},
    Map<String, Category> categoryById = const {},
    Map<String, String> personNameById = const {},
  }) {
    final q = SearchQuery.parse(query);
    if (q.isEmpty) return const [];

    final splitExpenseTransactionIds = {for (final e in expenses) if (e.isSplit) e.transactionId};

    final results = <SearchResult>[
      ..._transactions(q, transactions, splitExpenseTransactionIds, accountNameById, categoryById),
      ..._splitExpenses(q, expenses, accountNameById, categoryById),
      ..._people(q, people),
      ..._bills(q, bills, accountNameById, categoryById),
      ..._emis(q, emis),
      ..._loans(q, loans, personNameById),
      ..._creditCards(q, creditCards, accountNameById),
      ..._accounts(q, accounts),
      ..._categories(q, categories),
    ];

    results.sort((a, b) {
      final byGroup = a.group.index.compareTo(b.group.index);
      if (byGroup != 0) return byGroup;
      final aDate = a.date;
      final bDate = b.date;
      if (aDate == null && bDate == null) return a.title.compareTo(b.title);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return results;
  }

  /// Plain transactions only — a split expense's account-balance
  /// transaction is excluded here so it isn't listed twice (it surfaces
  /// under [SearchResultGroup.splitExpenses] with its richer detail),
  /// mirroring how `HistoryBuilder` categorises the same pair.
  static Iterable<SearchResult> _transactions(
    SearchQuery q,
    List<Transaction> transactions,
    Set<String> splitExpenseTransactionIds,
    Map<String, String> accountNameById,
    Map<String, Category> categoryById,
  ) sync* {
    for (final t in transactions) {
      if (t.isDeleted || splitExpenseTransactionIds.contains(t.id)) continue;

      final category = categoryById[t.categoryId];
      final accountName = accountNameById[t.accountId];
      if (!q.matches([t.description, t.notes, category?.name, accountName, t.type.label], amount: t.amount)) {
        continue;
      }

      yield SearchResult(
        id: 'txn-${t.id}',
        group: SearchResultGroup.transactions,
        title: t.description.isNotEmpty ? t.description : t.type.label,
        subtitle: [category?.name, accountName].whereType<String>().join(' · '),
        icon: category != null ? CategoryIcons.iconFor(category.iconKey) : t.type.icon,
        amount: t.amount,
        date: t.dateTime,
        routePath: '${AppRoutes.transactions}/${t.id}',
      );
    }
  }

  static Iterable<SearchResult> _splitExpenses(
    SearchQuery q,
    List<Expense> expenses,
    Map<String, String> accountNameById,
    Map<String, Category> categoryById,
  ) sync* {
    for (final e in expenses) {
      if (e.isDeleted || !e.isSplit) continue;

      final category = categoryById[e.categoryId];
      final accountName = accountNameById[e.accountId];
      final participantNames = [for (final p in e.participants) p.name];
      if (!q.matches(
        [e.description, e.notes, category?.name, accountName, ...participantNames],
        amount: e.totalAmount,
      )) {
        continue;
      }

      final others = e.participants.where((p) => !p.isMe).length;
      yield SearchResult(
        id: 'split-${e.id}',
        group: SearchResultGroup.splitExpenses,
        title: e.description,
        subtitle: [
          if (others > 0) 'Split with $others ${others == 1 ? 'person' : 'people'}',
          if (category != null) category.name,
        ].join(' · '),
        icon: category != null ? CategoryIcons.iconFor(category.iconKey) : Icons.call_split_rounded,
        amount: e.totalAmount,
        date: e.date,
        routePath: '${AppRoutes.transactions}/${e.transactionId}',
      );
    }
  }

  static Iterable<SearchResult> _people(SearchQuery q, List<Person> people) sync* {
    for (final p in people) {
      if (p.isDeleted) continue;
      if (!q.matches([p.name, p.phone, p.email, p.notes], amount: p.currentBalance.abs())) continue;

      yield SearchResult(
        id: 'person-${p.id}',
        group: SearchResultGroup.people,
        title: p.name,
        subtitle: p.phone ?? p.email ?? 'Person history',
        icon: Icons.person_outline_rounded,
        routePath: '${AppRoutes.people}/${p.id}',
      );
    }
  }

  static Iterable<SearchResult> _bills(
    SearchQuery q,
    List<Bill> bills,
    Map<String, String> accountNameById,
    Map<String, Category> categoryById,
  ) sync* {
    for (final b in bills) {
      if (b.isDeleted) continue;

      final category = b.categoryId == null ? null : categoryById[b.categoryId!];
      final accountName = b.accountId == null ? null : accountNameById[b.accountId!];
      if (!q.matches([b.name, b.notes, category?.name, accountName], amount: b.amount)) continue;

      yield SearchResult(
        id: 'bill-${b.id}',
        group: SearchResultGroup.bills,
        title: b.name,
        subtitle: [if (category != null) category.name, b.recurrence.label].join(' · '),
        icon: Icons.receipt_long_outlined,
        amount: b.amount,
        date: b.dueDate,
        routePath: '${AppRoutes.bills}/${b.id}',
      );
    }
  }

  static Iterable<SearchResult> _emis(SearchQuery q, List<Emi> emis) sync* {
    for (final e in emis) {
      if (e.isDeleted) continue;
      if (!q.matches([e.name, e.lenderName], amount: e.principalAmount)) continue;

      yield SearchResult(
        id: 'emi-${e.id}',
        group: SearchResultGroup.emis,
        title: e.name,
        subtitle: e.lenderName ?? 'Monthly payment plan',
        icon: Icons.account_balance_outlined,
        amount: e.principalAmount,
        date: e.startDate,
        routePath: '${AppRoutes.emis}/${e.id}',
      );
    }
  }

  static Iterable<SearchResult> _loans(
    SearchQuery q,
    List<Loan> loans,
    Map<String, String> personNameById,
  ) sync* {
    for (final l in loans) {
      if (l.isDeleted) continue;

      final personName = personNameById[l.personId];
      if (!q.matches([l.name, personName], amount: l.loanAmount)) continue;

      yield SearchResult(
        id: 'loan-${l.id}',
        group: SearchResultGroup.loans,
        title: l.name ?? personName ?? 'Loan',
        subtitle: personName ?? 'Loan',
        icon: Icons.handshake_outlined,
        amount: l.loanAmount,
        date: l.loanDate,
        routePath: '${AppRoutes.loans}/${l.id}',
      );
    }
  }

  /// Cards have no name of their own — they're identified by the account
  /// they post to, exactly as `historyEntriesProvider` derives `cardName`.
  static Iterable<SearchResult> _creditCards(
    SearchQuery q,
    List<CreditCardProfile> creditCards,
    Map<String, String> accountNameById,
  ) sync* {
    for (final c in creditCards) {
      if (c.isDeleted) continue;

      final name = accountNameById[c.accountId] ?? 'Card';
      if (!q.matches([name, c.lastFourDigits, c.cardNetwork?.label], amount: c.creditLimit)) continue;

      yield SearchResult(
        id: 'card-${c.id}',
        group: SearchResultGroup.creditCards,
        title: name,
        subtitle: [
          if (c.cardNetwork != null) c.cardNetwork!.label,
          if (c.lastFourDigits != null) '•••• ${c.lastFourDigits}',
        ].join(' · '),
        icon: Icons.credit_card_outlined,
        routePath: '${AppRoutes.creditCards}/${c.id}',
      );
    }
  }

  static Iterable<SearchResult> _accounts(SearchQuery q, List<Account> accounts) sync* {
    for (final a in accounts) {
      if (a.isDeleted) continue;
      if (!q.matches([a.name, a.type.label], amount: a.currentBalance)) continue;

      yield SearchResult(
        id: 'account-${a.id}',
        group: SearchResultGroup.accounts,
        title: a.name,
        subtitle: a.type.label,
        icon: Icons.account_balance_wallet_outlined,
        amount: a.currentBalance,
        routePath: AppRoutes.accounts,
      );
    }
  }

  static Iterable<SearchResult> _categories(SearchQuery q, List<Category> categories) sync* {
    for (final c in categories) {
      if (c.isDeleted) continue;
      if (!q.matchesText([c.name])) continue;

      yield SearchResult(
        id: 'category-${c.id}',
        group: SearchResultGroup.categories,
        title: c.name,
        subtitle: c.type.name[0].toUpperCase() + c.type.name.substring(1),
        icon: CategoryIcons.iconFor(c.iconKey),
        routePath: AppRoutes.categories,
      );
    }
  }
}
