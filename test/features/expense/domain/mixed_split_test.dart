import 'package:finance_app/features/expense/domain/mixed_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveMixedSplit', () {
    test('splits equally when nothing is locked', () {
      final r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'a', locked: false, value: 0),
        MixedParticipantInput(key: 'b', locked: false, value: 0),
        MixedParticipantInput(key: 'c', locked: false, value: 0),
        MixedParticipantInput(key: 'd', locked: false, value: 0),
      ]);
      expect(r.error, isNull);
      expect(r.shares.map((s) => s.share), [1250, 1250, 1250, 1250]);
    });

    test('one manual amount, remainder split equally (example 1)', () {
      final r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 2000),
        MixedParticipantInput(key: 'B', locked: false, value: 0),
        MixedParticipantInput(key: 'C', locked: false, value: 0),
        MixedParticipantInput(key: 'D', locked: false, value: 0),
      ]);
      expect(r.error, isNull);
      expect(r.remaining, 3000);
      expect(r.shares.map((s) => s.share), [2000, 1000, 1000, 1000]);
    });

    test('multiple manual amounts, remainder split equally (example 2)', () {
      final r = resolveMixedSplit(10000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 3500),
        MixedParticipantInput(key: 'B', locked: true, value: 2000),
        MixedParticipantInput(key: 'C', locked: false, value: 0),
        MixedParticipantInput(key: 'D', locked: false, value: 0),
      ]);
      expect(r.error, isNull);
      expect(r.remaining, 4500);
      expect(r.shares.map((s) => s.share), [3500, 2000, 2250, 2250]);
    });

    test('all manual: remaining is zero and shares pass through untouched', () {
      final r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 2500),
        MixedParticipantInput(key: 'B', locked: true, value: 2500),
      ]);
      expect(r.error, isNull);
      expect(r.remaining, 0);
      expect(r.shares.map((s) => s.share), [2500, 2500]);
    });

    test('errors when manual amounts exceed the total', () {
      final r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 4000),
        MixedParticipantInput(key: 'B', locked: true, value: 2000),
        MixedParticipantInput(key: 'C', locked: false, value: 0),
      ]);
      expect(r.error, 'Assigned amount exceeds the expense total by ₹1000');
    });

    test("errors when all manual and they don't add up to the total", () {
      final r = resolveMixedSplit(983.79, const [
        MixedParticipantInput(key: 'A', locked: true, value: 400),
        MixedParticipantInput(key: 'B', locked: true, value: 245.95),
        MixedParticipantInput(key: 'C', locked: true, value: 245.94),
      ]);
      expect(r.error, contains('left unassigned'));
      expect(r.remaining, 91.9);
    });

    test('handles a single participant (auto)', () {
      final r = resolveMixedSplit(500, const [MixedParticipantInput(key: 'A', locked: false, value: 0)]);
      expect(r.error, isNull);
      expect(r.shares.single.share, 500);
    });

    test('handles a single participant fully manual', () {
      final r = resolveMixedSplit(500, const [MixedParticipantInput(key: 'A', locked: true, value: 500)]);
      expect(r.error, isNull);
      expect(r.shares.single.share, 500);
    });

    test('handles no participants', () {
      final r = resolveMixedSplit(500, const []);
      expect(r.shares, isEmpty);
      expect(r.error, isNull);
    });

    test('handles a zero total with all-auto participants', () {
      final r = resolveMixedSplit(0, const [
        MixedParticipantInput(key: 'A', locked: false, value: 0),
        MixedParticipantInput(key: 'B', locked: false, value: 0),
      ]);
      expect(r.error, isNull);
      expect(r.shares.map((s) => s.share), [0, 0]);
    });

    test('handles decimal / paise remainders, pushing the odd cent onto the last auto participant', () {
      final r = resolveMixedSplit(10, const [
        MixedParticipantInput(key: 'A', locked: false, value: 0),
        MixedParticipantInput(key: 'B', locked: false, value: 0),
        MixedParticipantInput(key: 'C', locked: false, value: 0),
      ]);
      expect(r.error, isNull);
      expect(r.shares.map((s) => s.share), [3.33, 3.33, 3.34]);
      expect(r.shares.fold(0.0, (sum, s) => sum + s.share), 10);
    });

    test('re-splits correctly after a participant is added post manual-assignment', () {
      var r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 2000),
        MixedParticipantInput(key: 'B', locked: false, value: 0),
      ]);
      expect(r.shares.map((s) => s.share), [2000, 3000]);

      r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 2000),
        MixedParticipantInput(key: 'B', locked: false, value: 0),
        MixedParticipantInput(key: 'C', locked: false, value: 0),
      ]);
      expect(r.shares.map((s) => s.share), [2000, 1500, 1500]);
    });

    test('re-splits correctly after a participant is removed post manual-assignment', () {
      final r = resolveMixedSplit(5000, const [
        MixedParticipantInput(key: 'A', locked: true, value: 2000),
        MixedParticipantInput(key: 'C', locked: false, value: 0),
      ]);
      expect(r.shares.map((s) => s.share), [2000, 3000]);
    });
  });
}
