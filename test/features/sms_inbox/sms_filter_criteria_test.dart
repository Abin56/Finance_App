import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/sms_inbox/domain/filter/sms_card_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/filter/sms_date_range_filter.dart';
import 'package:finance_app/features/sms_inbox/domain/filter/sms_filter_criteria.dart';
import 'package:finance_app/features/sms_inbox/domain/filter/sms_sort_order.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_duplicate_reason.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';

/// Fixed "now" so month-relative presets can't flake around month boundaries.
final _now = DateTime(2026, 3, 15, 12);

SmsInboxItem _item({
  required String id,
  DateTime? date,
  double? amount,
  SmsTransactionDirection direction = SmsTransactionDirection.debit,
  SmsImportStatus status = SmsImportStatus.pending,
  String? bank,
  String? merchant,
  String? lastFour,
  SmsTransactionCategory category = SmsTransactionCategory.bankDebit,
  bool parsed = true,
  String? duplicateOf,
}) {
  final when = date ?? _now;
  return SmsInboxItem(
    id: id,
    messageKey: 'msg-$id',
    rawMessage: RawSmsMessage(address: bank ?? 'VM-BANK', body: 'body $id', date: when),
    dedupKey: id,
    duplicateOfId: duplicateOf,
    duplicateReason: duplicateOf == null ? null : SmsDuplicateReason.sameReferenceNumber,
    status: status,
    createdAt: when,
    parsed: !parsed
        ? null
        : ParsedSmsTransaction(
            amount: amount ?? 100,
            direction: direction,
            dateTime: when,
            category: category,
            confidence: 0.9,
            rawBody: 'body $id',
            merchantOrSender: merchant,
            bankName: bank,
            maskedAccountOrCard: lastFour,
          ),
  );
}

CreditCardProfile _card(String id, {String? lastFour}) => CreditCardProfile(
      id: id,
      accountId: 'acc-$id',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      createdAt: DateTime(2026),
      lastFourDigits: lastFour,
    );

SmsFilterContext _context({List<CreditCardProfile> cards = const []}) =>
    SmsFilterContext(now: _now, cardMatcher: SmsCardMatcher.fromCards(cards));

List<String> _ids(List<SmsInboxItem> items) => items.map((i) => i.id).toList();

void main() {
  group('facet combinations', () {
    test('Incoming + This Month', () {
      final items = [
        _item(id: 'in-this-month', direction: SmsTransactionDirection.credit, date: DateTime(2026, 3, 2)),
        _item(id: 'out-this-month', direction: SmsTransactionDirection.debit, date: DateTime(2026, 3, 2)),
        _item(id: 'in-last-month', direction: SmsTransactionDirection.credit, date: DateTime(2026, 2, 2)),
      ];

      const criteria = SmsFilterCriteria(
        direction: SmsMoneyDirection.incoming,
        datePreset: SmsDatePreset.thisMonth,
      );

      expect(_ids(criteria.apply(items, _context())), ['in-this-month']);
    });

    test('Outgoing + Last Month', () {
      final items = [
        _item(id: 'out-last-month', direction: SmsTransactionDirection.debit, date: DateTime(2026, 2, 20)),
        _item(id: 'in-last-month', direction: SmsTransactionDirection.credit, date: DateTime(2026, 2, 20)),
        _item(id: 'out-this-month', direction: SmsTransactionDirection.debit, date: DateTime(2026, 3, 1)),
      ];

      const criteria = SmsFilterCriteria(
        direction: SmsMoneyDirection.outgoing,
        datePreset: SmsDatePreset.lastMonth,
      );

      expect(_ids(criteria.apply(items, _context())), ['out-last-month']);
    });

    test('SBI + Pending', () {
      final items = [
        _item(id: 'sbi-pending', bank: 'SBI', status: SmsImportStatus.pending),
        _item(id: 'sbi-imported', bank: 'SBI', status: SmsImportStatus.imported),
        _item(id: 'hdfc-pending', bank: 'HDFC', status: SmsImportStatus.pending),
      ];

      const criteria = SmsFilterCriteria(banks: {'SBI'}, statuses: {SmsImportStatus.pending});

      expect(_ids(criteria.apply(items, _context())), ['sbi-pending']);
    });

    test('₹5000+ and Converted', () {
      final items = [
        _item(id: 'big-imported', amount: 7500, status: SmsImportStatus.imported),
        _item(id: 'small-imported', amount: 200, status: SmsImportStatus.imported),
        _item(id: 'big-pending', amount: 9000, status: SmsImportStatus.pending),
      ];

      const criteria = SmsFilterCriteria(minAmount: 5000, statuses: {SmsImportStatus.imported});

      expect(_ids(criteria.apply(items, _context())), ['big-imported']);
    });

    test('custom date range covers whole end day and excludes either side', () {
      final items = [
        _item(id: 'before', date: DateTime(2026, 3, 4, 23, 59)),
        _item(id: 'start-day', date: DateTime(2026, 3, 5, 0, 1)),
        // Late on the last day: the classic off-by-one an inclusive end drops.
        _item(id: 'end-day-late', date: DateTime(2026, 3, 7, 23, 30)),
        _item(id: 'after', date: DateTime(2026, 3, 8, 0, 5)),
      ];

      final criteria = SmsFilterCriteria(
        datePreset: SmsDatePreset.custom,
        customStart: DateTime(2026, 3, 5),
        customEnd: DateTime(2026, 3, 7),
      );

      // Newest-first is the default sort, so the later day leads.
      expect(_ids(criteria.apply(items, _context())), ['end-day-late', 'start-day']);
    });

    test('five facets combined narrow to the one matching message', () {
      final items = [
        _item(
          id: 'match',
          direction: SmsTransactionDirection.debit,
          date: DateTime(2026, 3, 3),
          bank: 'SBI',
          status: SmsImportStatus.pending,
          amount: 2500,
          category: SmsTransactionCategory.upiPayment,
        ),
        // Each of these differs from `match` in exactly one facet.
        _item(id: 'wrong-direction', direction: SmsTransactionDirection.credit, date: DateTime(2026, 3, 3), bank: 'SBI', amount: 2500, category: SmsTransactionCategory.upiPayment),
        _item(id: 'wrong-month', direction: SmsTransactionDirection.debit, date: DateTime(2026, 1, 3), bank: 'SBI', amount: 2500, category: SmsTransactionCategory.upiPayment),
        _item(id: 'wrong-bank', direction: SmsTransactionDirection.debit, date: DateTime(2026, 3, 3), bank: 'HDFC', amount: 2500, category: SmsTransactionCategory.upiPayment),
        _item(id: 'wrong-amount', direction: SmsTransactionDirection.debit, date: DateTime(2026, 3, 3), bank: 'SBI', amount: 50, category: SmsTransactionCategory.upiPayment),
        _item(id: 'wrong-status', direction: SmsTransactionDirection.debit, date: DateTime(2026, 3, 3), bank: 'SBI', amount: 2500, status: SmsImportStatus.ignored, category: SmsTransactionCategory.upiPayment),
        _item(id: 'wrong-category', direction: SmsTransactionDirection.debit, date: DateTime(2026, 3, 3), bank: 'SBI', amount: 2500, category: SmsTransactionCategory.atmWithdrawal),
      ];

      const criteria = SmsFilterCriteria(
        categories: {SmsTransactionCategory.upiPayment},
        direction: SmsMoneyDirection.outgoing,
        datePreset: SmsDatePreset.thisMonth,
        banks: {'SBI'},
        statuses: {SmsImportStatus.pending},
        minAmount: 1000,
      );

      expect(_ids(criteria.apply(items, _context())), ['match']);
    });

    test('no facets set returns everything', () {
      final items = [_item(id: 'a'), _item(id: 'b', parsed: false)];
      expect(_ids(const SmsFilterCriteria().apply(items, _context())).length, 2);
    });
  });

  group('card matching', () {
    test('matches a card by last-4 and buckets the rest as unknown', () {
      final cards = [_card('visa', lastFour: '1234')];
      final items = [
        _item(id: 'on-card', lastFour: '1234'),
        _item(id: 'other-card', lastFour: '9999'),
        _item(id: 'no-digits'),
      ];

      const onCard = SmsFilterCriteria(cardIds: {'visa'});
      expect(_ids(onCard.apply(items, _context(cards: cards))), ['on-card']);

      const unknown = SmsFilterCriteria(cardIds: {SmsCardMatcher.unknownCardId});
      expect(_ids(unknown.apply(items, _context(cards: cards))), ['other-card', 'no-digits']);
    });

    test('never guesses when two cards share a last-4', () {
      final cards = [_card('a', lastFour: '1234'), _card('b', lastFour: '1234')];
      final matcher = SmsCardMatcher.fromCards(cards);

      expect(matcher.cardIdFor(_item(id: 'x', lastFour: '1234')), SmsCardMatcher.unknownCardId);
      expect(matcher.matchableCardIds, isEmpty);
      expect(matcher.hasMatchableCards, isFalse, reason: 'an ambiguous card cannot be offered as a filter');
    });

    test('a card with no last-4 is not offered', () {
      final matcher = SmsCardMatcher.fromCards([_card('a')]);
      expect(matcher.hasMatchableCards, isFalse);
    });
  });

  group('amount facet', () {
    test('unparsed messages are excluded rather than treated as zero', () {
      final items = [_item(id: 'parsed', amount: 900), _item(id: 'unparsed', parsed: false)];

      const min = SmsFilterCriteria(minAmount: 100);
      expect(_ids(min.apply(items, _context())), ['parsed']);
    });

    test('min and max bound a window', () {
      final items = [
        _item(id: 'below', amount: 99),
        _item(id: 'inside', amount: 500),
        _item(id: 'above', amount: 5000),
      ];

      const criteria = SmsFilterCriteria(minAmount: 100, maxAmount: 1000);
      expect(_ids(criteria.apply(items, _context())), ['inside']);
    });
  });

  group('sorting', () {
    final items = [
      _item(id: 'mid', amount: 500, date: DateTime(2026, 3, 2), merchant: 'Bravo'),
      _item(id: 'high', amount: 900, date: DateTime(2026, 3, 3), merchant: 'Alpha'),
      _item(id: 'low', amount: 100, date: DateTime(2026, 3, 1), merchant: 'Charlie'),
    ];

    test('newest and oldest first', () {
      expect(_ids(const SmsFilterCriteria().apply(items, _context())), ['high', 'mid', 'low']);
      expect(
        _ids(const SmsFilterCriteria(sort: SmsSortOrder.oldestFirst).apply(items, _context())),
        ['low', 'mid', 'high'],
      );
    });

    test('highest and lowest amount', () {
      expect(
        _ids(const SmsFilterCriteria(sort: SmsSortOrder.highestAmount).apply(items, _context())),
        ['high', 'mid', 'low'],
      );
      expect(
        _ids(const SmsFilterCriteria(sort: SmsSortOrder.lowestAmount).apply(items, _context())),
        ['low', 'mid', 'high'],
      );
    });

    test('alphabetical by merchant', () {
      expect(
        _ids(const SmsFilterCriteria(sort: SmsSortOrder.alphabetical).apply(items, _context())),
        ['high', 'mid', 'low'],
      );
    });

    test('unparsed messages sort last by amount rather than as zero', () {
      final withUnparsed = [_item(id: 'unparsed', parsed: false), _item(id: 'cheap', amount: 1)];

      expect(
        _ids(const SmsFilterCriteria(sort: SmsSortOrder.lowestAmount).apply(withUnparsed, _context())),
        ['cheap', 'unparsed'],
        reason: 'a blank amount is not a small amount',
      );
    });
  });

  group('active chips', () {
    List<String> labels(SmsFilterCriteria criteria) =>
        criteria.chips(cardLabel: (id) => 'Card', formatAmount: (a) => '₹${a.toStringAsFixed(0)}').map((c) => c.label).toList();

    test('one chip per active value, and sort is not a filter', () {
      const criteria = SmsFilterCriteria(
        direction: SmsMoneyDirection.outgoing,
        datePreset: SmsDatePreset.thisMonth,
        banks: {'SBI'},
        statuses: {SmsImportStatus.pending},
        minAmount: 1000,
        sort: SmsSortOrder.alphabetical,
      );

      expect(criteria.activeCount, 5);
      expect(labels(criteria), ['Outgoing money', 'This month', 'SBI', 'Pending review', '₹1000+']);
    });

    test('removing a chip drops only that facet', () {
      const criteria = SmsFilterCriteria(
        direction: SmsMoneyDirection.outgoing,
        banks: {'SBI', 'HDFC'},
        minAmount: 1000,
      );

      final chips = criteria.chips(cardLabel: (id) => 'Card', formatAmount: (a) => '₹${a.toStringAsFixed(0)}');
      final withoutSbi = chips.firstWhere((c) => c.label == 'SBI').removed;

      expect(withoutSbi.banks, {'HDFC'});
      expect(withoutSbi.direction, SmsMoneyDirection.outgoing, reason: 'other facets survive');
      expect(withoutSbi.minAmount, 1000);
    });

    test('Clear All drops every facet but keeps the chosen sort', () {
      const criteria = SmsFilterCriteria(
        banks: {'SBI'},
        minAmount: 1000,
        sort: SmsSortOrder.highestAmount,
      );

      final cleared = criteria.cleared();
      expect(cleared.hasActiveFilters, isFalse);
      expect(cleared.activeCount, 0);
      expect(cleared.sort, SmsSortOrder.highestAmount);
    });

    test('Clear All keeps you inside the duplicates review', () {
      const criteria = SmsFilterCriteria(banks: {'SBI'}, duplicates: SmsDuplicateVisibility.only);

      final cleared = criteria.cleared();
      expect(cleared.banks, isEmpty);
      expect(
        cleared.duplicates,
        SmsDuplicateVisibility.only,
        reason: 'clearing filters mid-review should widen the review, not eject you from it',
      );
    });
  });

  group('duplicates facet', () {
    final items = [_item(id: 'original'), _item(id: 'copy', duplicateOf: 'original')];

    test('the default inbox hides flagged duplicates', () {
      expect(_ids(const SmsFilterCriteria().apply(items, _context())), ['original']);
    });

    test('the Duplicates filter shows only flagged duplicates', () {
      const criteria = SmsFilterCriteria(duplicates: SmsDuplicateVisibility.only);
      expect(_ids(criteria.apply(items, _context())), ['copy']);
    });

    test('no other facet can surface a duplicate into the main inbox', () {
      // The whole point of storing duplicates is that they stay out of the
      // way; a filter combination that leaked one back into the feed would
      // defeat it.
      const criteria = SmsFilterCriteria(statuses: {SmsImportStatus.pending});
      expect(_ids(criteria.apply(items, _context())), ['original']);
    });

    test('hiding duplicates is not counted as an active filter', () {
      // It's the normal state of the inbox, not something the user turned on.
      expect(const SmsFilterCriteria().activeCount, 0);
      expect(const SmsFilterCriteria(duplicates: SmsDuplicateVisibility.only).activeCount, 1);
    });
  });
}
