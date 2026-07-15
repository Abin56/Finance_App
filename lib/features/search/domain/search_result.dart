import 'package:flutter/material.dart';

/// Which section of the global Search screen a [SearchResult] is listed
/// under. Ordered as declared — [SearchBuilder] emits groups in this order
/// so the most-searched-for things (money movements, then people) surface
/// above configuration-ish matches (accounts, categories).
enum SearchResultGroup {
  transactions,
  splitExpenses,
  people,
  bills,
  emis,
  loans,
  creditCards,
  accounts,
  categories,
}

extension SearchResultGroupX on SearchResultGroup {
  String get label {
    switch (this) {
      case SearchResultGroup.transactions:
        return 'Transactions';
      case SearchResultGroup.splitExpenses:
        return 'Shared expenses';
      case SearchResultGroup.people:
        return 'People';
      case SearchResultGroup.bills:
        return 'Bills';
      case SearchResultGroup.emis:
        return 'EMI';
      case SearchResultGroup.loans:
        return 'Loans';
      case SearchResultGroup.creditCards:
        return 'Credit cards';
      case SearchResultGroup.accounts:
        return 'Accounts';
      case SearchResultGroup.categories:
        return 'Categories';
    }
  }
}

/// One row on the global Search screen. A presentation-layer view model
/// only — never persisted, and built fresh per query by [SearchBuilder]
/// from streams every feature already exposes. Mirrors `HistoryEntry`'s
/// shape deliberately: both are "normalize many features into one list"
/// view models, and keeping them similar keeps the two screens' tiles
/// consistent.
class SearchResult {
  const SearchResult({
    required this.id,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.amount,
    this.date,
    this.routePath,
  });

  final String id;
  final SearchResultGroup group;
  final String title;

  /// Context line — what matched, or what this thing is (e.g. a
  /// transaction's "Food · HDFC", a person's phone number).
  final String subtitle;

  final IconData icon;

  /// Always positive when set; Search shows magnitude only, since it isn't
  /// a ledger view — direction/status belong on the detail screen.
  final double? amount;

  final DateTime? date;

  /// Where tapping navigates, if anywhere.
  final String? routePath;
}
