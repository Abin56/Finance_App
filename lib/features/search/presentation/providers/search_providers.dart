import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/search_builder.dart';
import '../../domain/search_result.dart';

/// The current global-search query. A [StateProvider] rather than screen
/// state so the results provider can stay a plain derived `Provider`.
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Grouped global-search results for [searchQueryProvider] — reads only
/// streams each feature already exposes, and defers all matching to
/// [SearchBuilder], so Search can never disagree with the feature screens
/// it points at.
final searchResultsProvider = Provider.autoDispose<List<SearchResult>>((ref) {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return const [];

  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  final categories = ref.watch(categoriesStreamProvider).value ?? const [];
  final people = ref.watch(peopleStreamProvider).value ?? const [];

  return SearchBuilder.build(
    query: query,
    transactions: ref.watch(transactionsStreamProvider).value ?? const [],
    expenses: ref.watch(expensesStreamProvider).value ?? const [],
    people: people,
    accounts: accounts,
    categories: categories,
    loans: ref.watch(loansStreamProvider).value ?? const [],
    emis: ref.watch(emisStreamProvider).value ?? const [],
    bills: ref.watch(billsStreamProvider).value ?? const [],
    creditCards: ref.watch(creditCardsStreamProvider).value ?? const [],
    accountNameById: {for (final a in accounts) a.id: a.name},
    categoryById: {for (final c in categories) c.id: c},
    personNameById: {for (final p in people) p.id: p.name},
  );
});
