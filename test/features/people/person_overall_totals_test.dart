import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person_overall_totals.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerEntry _entry({
  required String id,
  required LedgerEntryType type,
  required double amount,
  DateTime? deletedAt,
}) {
  return LedgerEntry(
    id: id,
    personId: 'p1',
    type: type,
    amount: amount,
    date: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
  )..deletedAt = deletedAt;
}

void main() {
  group('PersonOverallTotals.from', () {
    // Case 6: a person can owe you on some transactions and you owe them on
    // others, at the same time — totals must split by direction rather than
    // netting, while netBalance still matches the netted sign convention.
    test('splits mixed-direction entries into independent You Owe / They Owe totals', () {
      final entries = [
        _entry(id: 'l1', type: LedgerEntryType.gave, amount: 300), // they owe you +300
        _entry(id: 'l2', type: LedgerEntryType.borrowed, amount: 120), // you owe them +120 (signed -120)
      ];

      final totals = PersonOverallTotals.from(entries);

      expect(totals.totalTheyOwe, 300);
      expect(totals.totalYouOwe, 120);
      expect(totals.netBalance, 180);
    });

    test('excludes soft-deleted entries from every total', () {
      final entries = [
        _entry(id: 'l1', type: LedgerEntryType.gave, amount: 300),
        _entry(id: 'l2', type: LedgerEntryType.gave, amount: 999, deletedAt: DateTime(2026, 1, 2)),
      ];

      final totals = PersonOverallTotals.from(entries);

      expect(totals.totalTheyOwe, 300);
      expect(totals.netBalance, 300);
    });

    test('the fold does not collapse or remove source entries', () {
      final entries = [
        _entry(id: 'l1', type: LedgerEntryType.gave, amount: 300),
        _entry(id: 'l2', type: LedgerEntryType.borrowed, amount: 120),
        _entry(id: 'l3', type: LedgerEntryType.receivedBack, amount: 50),
      ];

      PersonOverallTotals.from(entries);

      // Computing totals is a pure read — the caller's list is untouched.
      expect(entries, hasLength(3));
      expect(entries.map((e) => e.id), ['l1', 'l2', 'l3']);
    });

    test('an all-zero/empty ledger produces zero totals', () {
      final totals = PersonOverallTotals.from(const []);

      expect(totals.totalYouOwe, 0);
      expect(totals.totalTheyOwe, 0);
      expect(totals.netBalance, 0);
    });

    test('repaid/receivedBack entries reduce/build the correct direction', () {
      final entries = [
        _entry(id: 'l1', type: LedgerEntryType.gave, amount: 300),
        _entry(id: 'l2', type: LedgerEntryType.receivedBack, amount: 100), // -100
      ];

      final totals = PersonOverallTotals.from(entries);

      // receivedBack is negative-signed, so it adds to totalYouOwe under
      // this fold's direction split, even though its net effect reduces
      // what they owe overall — netBalance reflects that correctly.
      expect(totals.totalTheyOwe, 300);
      expect(totals.totalYouOwe, 100);
      expect(totals.netBalance, 200);
    });
  });
}
