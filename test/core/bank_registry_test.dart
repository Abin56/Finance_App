import 'package:finance_app/core/data/bank_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankRegistry.byId', () {
    test('resolves a known bank', () {
      expect(BankRegistry.byId('sbi')?.name, 'State Bank of India');
    });

    test('returns null for an unknown id', () {
      expect(BankRegistry.byId('not_a_real_bank'), isNull);
    });

    test('returns null for null/empty id', () {
      expect(BankRegistry.byId(null), isNull);
      expect(BankRegistry.byId(''), isNull);
    });
  });

  group('BankRegistry.matchByName', () {
    test('matches an exact name (case-insensitive)', () {
      expect(BankRegistry.matchByName('state bank of india')?.id, 'sbi');
    });

    test('matches a short code', () {
      expect(BankRegistry.matchByName('HDFC')?.id, 'hdfc');
    });

    test('fuzzy-matches a name containing the bank name', () {
      expect(BankRegistry.matchByName('ICICI Bank - Main Branch')?.id, 'icici');
    });

    test('returns null when nothing matches', () {
      expect(BankRegistry.matchByName('My Local Cooperative Society'), isNull);
    });
  });

  group('BankRegistry.resolve', () {
    test('prefers bankId over fallbackName', () {
      expect(BankRegistry.resolve(bankId: 'axis', fallbackName: 'HDFC Bank')?.id, 'axis');
    });

    test('falls back to name matching when bankId is null', () {
      expect(BankRegistry.resolve(bankId: null, fallbackName: 'Kotak Mahindra Bank')?.id, 'kotak');
    });

    test('returns null when neither resolves', () {
      expect(BankRegistry.resolve(bankId: null, fallbackName: 'Some Unknown Bank'), isNull);
    });
  });

  group('BankRegistry.all — data integrity', () {
    test('every bank has a unique id', () {
      final ids = BankRegistry.all.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every bank has a non-empty shortCode and name', () {
      for (final bank in BankRegistry.all) {
        expect(bank.shortCode, isNotEmpty, reason: '${bank.id} has an empty shortCode');
        expect(bank.name, isNotEmpty, reason: '${bank.id} has an empty name');
      }
    });

    test('generic is not part of the selectable list', () {
      expect(BankRegistry.all.any((b) => b.id == BankRegistry.generic.id), isFalse);
    });
  });

  group('BankRegistry.frequent / groupedByLetter', () {
    test('frequent only contains banks flagged isFrequent', () {
      expect(BankRegistry.frequent, isNotEmpty);
      expect(BankRegistry.frequent.every((b) => b.isFrequent), isTrue);
    });

    test('groupedByLetter buckets every bank under its first letter', () {
      final grouped = BankRegistry.groupedByLetter;
      final totalGrouped = grouped.values.fold(0, (sum, list) => sum + list.length);
      expect(totalGrouped, BankRegistry.all.length);
      for (final entry in grouped.entries) {
        for (final bank in entry.value) {
          expect(bank.name.toUpperCase().startsWith(entry.key), isTrue);
        }
      }
    });
  });
}
