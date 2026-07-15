import 'package:finance_app/features/sms_inbox/domain/sms_dedup_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = DateTime(2026, 7, 15, 14, 45);

  group('SmsDedupKey.compute', () {
    test('same inputs produce the same key', () {
      final a = SmsDedupKey.compute(
        sender: 'VM-HDFCBK',
        dateTime: date,
        amount: 1250.0,
        referenceNumber: '123456789012',
        body: 'Rs.1,250.00 debited...',
      );
      final b = SmsDedupKey.compute(
        sender: 'VM-HDFCBK',
        dateTime: date,
        amount: 1250.0,
        referenceNumber: '123456789012',
        body: 'Rs.1,250.00 debited...',
      );
      expect(a, equals(b));
    });

    test('sender DLT-prefix variants collapse to the same key', () {
      final a = SmsDedupKey.compute(
        sender: 'VM-HDFCBK',
        dateTime: date,
        amount: 1250.0,
        referenceNumber: '123456789012',
        body: 'irrelevant',
      );
      final b = SmsDedupKey.compute(
        sender: 'AX-HDFCBK',
        dateTime: date,
        amount: 1250.0,
        referenceNumber: '123456789012',
        body: 'irrelevant',
      );
      expect(a, equals(b));
    });

    test('different amount produces a different key', () {
      final a = SmsDedupKey.compute(sender: 'VM-HDFCBK', dateTime: date, amount: 1250.0, body: 'x');
      final b = SmsDedupKey.compute(sender: 'VM-HDFCBK', dateTime: date, amount: 1251.0, body: 'x');
      expect(a, isNot(equals(b)));
    });

    test('different timestamp produces a different key', () {
      final a = SmsDedupKey.compute(sender: 'VM-HDFCBK', dateTime: date, amount: 1250.0, body: 'x');
      final b = SmsDedupKey.compute(
        sender: 'VM-HDFCBK',
        dateTime: date.add(const Duration(minutes: 1)),
        amount: 1250.0,
        body: 'x',
      );
      expect(a, isNot(equals(b)));
    });

    test('different reference number produces a different key', () {
      final a = SmsDedupKey.compute(
        sender: 'VM-HDFCBK',
        dateTime: date,
        amount: 1250.0,
        referenceNumber: '111111',
        body: 'x',
      );
      final b = SmsDedupKey.compute(
        sender: 'VM-HDFCBK',
        dateTime: date,
        amount: 1250.0,
        referenceNumber: '222222',
        body: 'x',
      );
      expect(a, isNot(equals(b)));
    });

    test('falls back to body when no reference number is available', () {
      final a = SmsDedupKey.compute(sender: 'VM-HDFCBK', dateTime: date, amount: 1250.0, body: 'body one');
      final b = SmsDedupKey.compute(sender: 'VM-HDFCBK', dateTime: date, amount: 1250.0, body: 'body two');
      expect(a, isNot(equals(b)));
    });
  });
}
