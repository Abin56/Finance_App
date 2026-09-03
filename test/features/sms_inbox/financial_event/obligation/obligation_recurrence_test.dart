import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Safety rule 15: a single observation is never declared recurring', () {
    final recurrence = ObligationRecurrence.singleObservation(
      DateTime(2026, 9, 1),
    );
    expect(recurrence.isConfirmedRecurring, isFalse);
    expect(recurrence.interval, RecurrenceInterval.unknown);
    expect(recurrence.occurrenceCount, 1);
  });

  test(
    'two observations are enough to estimate an interval, but confidence stays low',
    () {
      const tracker = ObligationRecurrenceTracker();
      var recurrence = ObligationRecurrence.singleObservation(
        DateTime(2026, 7, 1),
      );
      recurrence = tracker.observe(recurrence, DateTime(2026, 8, 1));

      expect(recurrence.occurrenceCount, 2);
      expect(recurrence.interval, RecurrenceInterval.monthly);
      expect(recurrence.isConfirmedRecurring, isTrue);
      expect(recurrence.confidence, lessThan(0.5));
    },
  );

  test('confidence grows with more consistent monthly observations', () {
    const tracker = ObligationRecurrenceTracker();
    var recurrence = ObligationRecurrence.singleObservation(
      DateTime(2026, 6, 1),
    );
    recurrence = tracker.observe(recurrence, DateTime(2026, 7, 1));
    final afterTwo = recurrence.confidence;

    recurrence = tracker.observe(recurrence, DateTime(2026, 8, 1));
    final afterThree = recurrence.confidence;

    recurrence = tracker.observe(recurrence, DateTime(2026, 9, 1));
    final afterFour = recurrence.confidence;

    expect(afterThree, greaterThan(afterTwo));
    expect(afterFour, greaterThan(afterThree));
    expect(recurrence.occurrenceCount, 4);
    expect(recurrence.interval, RecurrenceInterval.monthly);
  });

  test('irregular gaps produce lower confidence than consistent gaps', () {
    const tracker = ObligationRecurrenceTracker();

    var consistent = ObligationRecurrence.singleObservation(
      DateTime(2026, 1, 1),
    );
    consistent = tracker.observe(consistent, DateTime(2026, 2, 1));
    consistent = tracker.observe(consistent, DateTime(2026, 3, 1));

    var irregular = ObligationRecurrence.singleObservation(
      DateTime(2026, 1, 1),
    );
    irregular = tracker.observe(irregular, DateTime(2026, 1, 20));
    irregular = tracker.observe(irregular, DateTime(2026, 4, 15));

    expect(consistent.confidence, greaterThan(irregular.confidence));
  });

  test(
    'daily/weekly/quarterly/yearly gaps classify into the right interval',
    () {
      const tracker = ObligationRecurrenceTracker();

      RecurrenceInterval intervalFor(int gapDays) {
        var r = ObligationRecurrence.singleObservation(DateTime(2026, 1, 1));
        r = tracker.observe(
          r,
          DateTime(2026, 1, 1).add(Duration(days: gapDays)),
        );
        return r.interval;
      }

      expect(intervalFor(1), RecurrenceInterval.daily);
      expect(intervalFor(7), RecurrenceInterval.weekly);
      expect(intervalFor(30), RecurrenceInterval.monthly);
      expect(intervalFor(90), RecurrenceInterval.quarterly);
      expect(intervalFor(365), RecurrenceInterval.yearly);
      expect(intervalFor(600), RecurrenceInterval.custom);
    },
  );

  test('nextExpectedOccurrence projects forward from the last observation', () {
    const tracker = ObligationRecurrenceTracker();
    var recurrence = ObligationRecurrence.singleObservation(
      DateTime(2026, 7, 1),
    );
    recurrence = tracker.observe(recurrence, DateTime(2026, 8, 1));

    expect(recurrence.nextExpectedOccurrence, isNotNull);
    expect(recurrence.lastOccurrence, DateTime(2026, 8, 1));
  });
}
