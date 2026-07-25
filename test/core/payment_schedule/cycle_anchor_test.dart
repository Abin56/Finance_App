import 'package:finance_app/core/payment_schedule/domain/cycle_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Direct coverage for [CycleAnchor] in isolation — before this file, the
/// only exercise this type got was indirectly through
/// `PersonTimelineCycleItem` in `person_timeline_cycle_item_test.dart`. These
/// tests pin the exact month-boundary/day-clamping behavior every adapter
/// (Credit Cards, People, and any future adopter) relies on, so a future
/// change to this frozen file can't silently shift carry-forward behavior
/// app-wide without a test failing here first.
void main() {
  group('CycleAnchor.currentCycleFor', () {
    test('now before this month\'s anchor day -> current cycle ends this month', () {
      const anchor = CycleAnchor(anchorDay: 17);
      final period = anchor.currentCycleFor(now: DateTime(2026, 7, 10));

      expect(period.start, DateTime(2026, 6, 18));
      expect(period.end, DateTime(2026, 7, 17));
    });

    test('now on the anchor day itself -> that day is the end of the current cycle', () {
      const anchor = CycleAnchor(anchorDay: 17);
      final period = anchor.currentCycleFor(now: DateTime(2026, 7, 17));

      expect(period.start, DateTime(2026, 6, 18));
      expect(period.end, DateTime(2026, 7, 17));
    });

    test('now after this month\'s anchor day -> current cycle rolls to next month\'s anchor', () {
      const anchor = CycleAnchor(anchorDay: 17);
      final period = anchor.currentCycleFor(now: DateTime(2026, 7, 22));

      expect(period.start, DateTime(2026, 7, 18));
      expect(period.end, DateTime(2026, 8, 17));
    });

    test('anchor day beyond a short month clamps to that month\'s last day', () {
      const anchor = CycleAnchor(anchorDay: 31);
      final period = anchor.currentCycleFor(now: DateTime(2026, 2, 20));

      // Feb 2026 has 28 days; the anchor clamps rather than overflowing.
      expect(period.end, DateTime(2026, 2, 28));
    });
  });

  group('CycleAnchor.previousCycleFor', () {
    test('is the cycle immediately before currentCycleFor', () {
      const anchor = CycleAnchor(anchorDay: 17);
      final previous = anchor.previousCycleFor(now: DateTime(2026, 7, 22));

      expect(previous.start, DateTime(2026, 6, 18));
      expect(previous.end, DateTime(2026, 7, 17));
    });
  });

  group('CycleAnchor.classify', () {
    const anchor = CycleAnchor(anchorDay: 17);
    final now = DateTime(2026, 7, 22); // current cycle: 18 Jul -> 17 Aug

    test('a date inside the current window classifies as current', () {
      expect(anchor.classify(DateTime(2026, 7, 20), now: now), CycleClassification.current);
    });

    test('a date on the current window\'s start boundary classifies as current', () {
      expect(anchor.classify(DateTime(2026, 7, 18), now: now), CycleClassification.current);
    });

    test('a date on the current window\'s end boundary classifies as current', () {
      expect(anchor.classify(DateTime(2026, 8, 17), now: now), CycleClassification.current);
    });

    test('a date before the current window\'s start classifies as previous', () {
      expect(anchor.classify(DateTime(2026, 7, 17), now: now), CycleClassification.previous);
      expect(anchor.classify(DateTime(2026, 6, 1), now: now), CycleClassification.previous);
    });

    test('a date after the current window\'s end classifies as future', () {
      expect(anchor.classify(DateTime(2026, 8, 18), now: now), CycleClassification.future);
    });

    test('default anchor day is 17', () {
      expect(const CycleAnchor().anchorDay, 17);
    });
  });
}
