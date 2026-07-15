import '../sms_import_status.dart';
import '../sms_inbox_item.dart';
import '../sms_transaction_category.dart';
import '../sms_transaction_direction.dart';
import 'sms_card_matcher.dart';
import 'sms_date_range_filter.dart';
import 'sms_sort_order.dart';

/// Whether the feed shows real messages or the flagged-duplicate pile.
///
/// Deliberately not a "show everything" option: a duplicate and its original
/// are near-identical by construction, so interleaving them is precisely the
/// confusing feed this facet exists to prevent. It is an either/or —
/// [hidden] is the clean default inbox, [only] is the review screen.
enum SmsDuplicateVisibility { hidden, only }

/// Which way the money moved, in the user's language rather than the bank's.
enum SmsMoneyDirection { any, incoming, outgoing }

extension SmsMoneyDirectionX on SmsMoneyDirection {
  String get label {
    switch (this) {
      case SmsMoneyDirection.any:
        return 'All';
      case SmsMoneyDirection.incoming:
        return 'Incoming money';
      case SmsMoneyDirection.outgoing:
        return 'Outgoing money';
    }
  }

  bool matches(SmsTransactionDirection? direction) {
    switch (this) {
      case SmsMoneyDirection.any:
        return true;
      case SmsMoneyDirection.incoming:
        return direction == SmsTransactionDirection.credit;
      case SmsMoneyDirection.outgoing:
        return direction == SmsTransactionDirection.debit;
    }
  }
}

/// Everything needed to evaluate a criteria against one item without the
/// domain reaching for `DateTime.now()` or a provider — which is what keeps
/// the matching pure and directly testable.
class SmsFilterContext {
  const SmsFilterContext({required this.now, required this.cardMatcher});

  final DateTime now;
  final SmsCardMatcher cardMatcher;
}

/// A chip rendered above the feed for one active filter value. [removed] is
/// the criteria you get by dropping just this chip, so the UI never has to
/// know which facet a chip came from.
class SmsFilterChipData {
  const SmsFilterChipData({required this.label, required this.removed});

  final String label;
  final SmsFilterCriteria removed;
}

/// The SMS Inbox's filter state: a set of independent facets ANDed together,
/// so "Incoming + This Month + SBI + Pending + ₹1000+" is just five facets
/// each narrowing the result.
///
/// Adding a future facet (merchant, category, tags, AI suggestions) means a
/// field here, a clause in [matches], an entry in [chips], and one section
/// widget — no change to how filtering, chips, or the sheet are structured.
/// Facets deliberately stay orthogonal: money direction, conversion status
/// and transaction category are separate dimensions rather than one flat
/// list, so no two controls can ever set the same underlying value.
///
/// Every facet reads only fields already on [SmsInboxItem]. There is no
/// account facet because [SmsInboxItem] carries no account link and
/// `Account` stores no last-4 to match one against; and no person facet
/// because an unconverted SMS has no person attribution at all.
class SmsFilterCriteria {
  const SmsFilterCriteria({
    this.categories = const {},
    this.direction = SmsMoneyDirection.any,
    this.datePreset = SmsDatePreset.any,
    this.customStart,
    this.customEnd,
    this.banks = const {},
    this.statuses = const {},
    this.minAmount,
    this.maxAmount,
    this.cardIds = const {},
    this.duplicates = SmsDuplicateVisibility.hidden,
    this.sort = SmsSortOrder.newestFirst,
  });

  final Set<SmsTransactionCategory> categories;
  final SmsMoneyDirection direction;
  final SmsDatePreset datePreset;
  final DateTime? customStart;
  final DateTime? customEnd;
  final Set<String> banks;
  final Set<SmsImportStatus> statuses;
  final double? minAmount;
  final double? maxAmount;
  final Set<String> cardIds;
  final SmsDuplicateVisibility duplicates;
  final SmsSortOrder sort;

  /// An empty set means "don't filter on this facet" rather than "match
  /// nothing" — that's what lets every section default to All.
  bool matches(SmsInboxItem item, SmsFilterContext context) {
    final parsed = item.parsed;

    // Checked first and unconditionally: a flagged duplicate must never
    // appear in the default feed no matter what other facets are set, and the
    // Duplicates review must never show anything else.
    if ((duplicates == SmsDuplicateVisibility.only) != item.isDuplicate) return false;

    if (categories.isNotEmpty && !categories.contains(parsed?.category)) return false;
    if (!direction.matches(parsed?.direction)) return false;
    if (statuses.isNotEmpty && !statuses.contains(item.status)) return false;

    final window = datePreset.resolve(context.now, customStart: customStart, customEnd: customEnd);
    if (window != null && !window.contains(item.rawMessage.date)) return false;

    if (banks.isNotEmpty && !banks.contains(parsed?.bankName)) return false;

    if (minAmount != null || maxAmount != null) {
      final amount = parsed?.amount;
      // An unparsed message has no amount to compare, so an amount filter
      // can only exclude it — claiming otherwise would be a guess.
      if (amount == null) return false;
      if (minAmount != null && amount < minAmount!) return false;
      if (maxAmount != null && amount > maxAmount!) return false;
    }

    if (cardIds.isNotEmpty && !cardIds.contains(context.cardMatcher.cardIdFor(item))) return false;

    return true;
  }

  /// Sorting lives with filtering so callers get the feed in one pass and
  /// can't accidentally sort a list they forgot to filter.
  List<SmsInboxItem> apply(List<SmsInboxItem> items, SmsFilterContext context) {
    final result = items.where((item) => matches(item, context)).toList();
    result.sort(sort.compare);
    return result;
  }

  bool get hasActiveFilters => activeCount > 0;

  /// Sort is excluded: it reorders the feed rather than narrowing it, so
  /// counting it would tell the user a filter is on when nothing is hidden.
  /// [duplicates] counts only when set to [SmsDuplicateVisibility.only]:
  /// hiding duplicates is the normal state of the inbox, not a filter the
  /// user turned on, so counting it would show a permanent "1 filter active".
  int get activeCount {
    return categories.length +
        (direction == SmsMoneyDirection.any ? 0 : 1) +
        (datePreset == SmsDatePreset.any ? 0 : 1) +
        banks.length +
        statuses.length +
        (minAmount != null ? 1 : 0) +
        (maxAmount != null ? 1 : 0) +
        cardIds.length +
        (duplicates == SmsDuplicateVisibility.only ? 1 : 0);
  }

  /// One removable chip per active value, each carrying the criteria that
  /// results from removing only itself.
  List<SmsFilterChipData> chips({required String Function(String cardId) cardLabel, required String Function(double) formatAmount}) {
    return [
      for (final category in categories)
        SmsFilterChipData(
          label: category.label,
          removed: copyWith(categories: categories.difference({category})),
        ),
      if (direction != SmsMoneyDirection.any)
        SmsFilterChipData(label: direction.label, removed: copyWith(direction: SmsMoneyDirection.any)),
      if (datePreset != SmsDatePreset.any)
        SmsFilterChipData(
          label: datePreset == SmsDatePreset.custom ? _customRangeLabel() : datePreset.label,
          removed: copyWith(datePreset: SmsDatePreset.any, clearCustomRange: true),
        ),
      for (final bank in banks)
        SmsFilterChipData(label: bank, removed: copyWith(banks: banks.difference({bank}))),
      for (final status in statuses)
        SmsFilterChipData(label: status.label, removed: copyWith(statuses: statuses.difference({status}))),
      if (minAmount != null)
        SmsFilterChipData(label: '${formatAmount(minAmount!)}+', removed: copyWith(clearMinAmount: true)),
      if (maxAmount != null)
        SmsFilterChipData(label: 'Up to ${formatAmount(maxAmount!)}', removed: copyWith(clearMaxAmount: true)),
      for (final cardId in cardIds)
        SmsFilterChipData(label: cardLabel(cardId), removed: copyWith(cardIds: cardIds.difference({cardId}))),
      if (duplicates == SmsDuplicateVisibility.only)
        SmsFilterChipData(
          label: 'Duplicates',
          removed: copyWith(duplicates: SmsDuplicateVisibility.hidden),
        ),
    ];
  }

  String _customRangeLabel() {
    final start = customStart;
    final end = customEnd;
    if (start == null || end == null) return SmsDatePreset.custom.label;
    return '${start.day}/${start.month} – ${end.day}/${end.month}';
  }

  /// Clears every facet but deliberately keeps [sort]: "Clear All" is about
  /// what's hidden, and silently re-ordering the feed would be a surprise.
  ///
  /// [duplicates] is likewise preserved: clearing filters while reviewing
  /// duplicates should widen what you see *within* the review, not eject you
  /// back to the main inbox mid-task.
  SmsFilterCriteria cleared() => SmsFilterCriteria(sort: sort, duplicates: duplicates);

  /// Explicit `clear*` flags because a plain `null` default can't distinguish
  /// "leave unchanged" from "set back to null".
  SmsFilterCriteria copyWith({
    Set<SmsTransactionCategory>? categories,
    SmsMoneyDirection? direction,
    SmsDatePreset? datePreset,
    DateTime? customStart,
    DateTime? customEnd,
    Set<String>? banks,
    Set<SmsImportStatus>? statuses,
    double? minAmount,
    double? maxAmount,
    Set<String>? cardIds,
    SmsDuplicateVisibility? duplicates,
    SmsSortOrder? sort,
    bool clearCustomRange = false,
    bool clearMinAmount = false,
    bool clearMaxAmount = false,
  }) {
    return SmsFilterCriteria(
      categories: categories ?? this.categories,
      direction: direction ?? this.direction,
      datePreset: datePreset ?? this.datePreset,
      customStart: clearCustomRange ? null : (customStart ?? this.customStart),
      customEnd: clearCustomRange ? null : (customEnd ?? this.customEnd),
      banks: banks ?? this.banks,
      statuses: statuses ?? this.statuses,
      minAmount: clearMinAmount ? null : (minAmount ?? this.minAmount),
      maxAmount: clearMaxAmount ? null : (maxAmount ?? this.maxAmount),
      cardIds: cardIds ?? this.cardIds,
      duplicates: duplicates ?? this.duplicates,
      sort: sort ?? this.sort,
    );
  }
}
