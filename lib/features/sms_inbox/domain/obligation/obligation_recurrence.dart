/// How often an obligation recurs — [unknown] is the honest default for a
/// single observation (see Safety rule 15: "never infer recurrence from one
/// observation").
enum RecurrenceInterval {
  daily,
  weekly,
  monthly,
  quarterly,
  yearly,
  custom,
  unknown,
}

extension RecurrenceIntervalX on RecurrenceInterval {
  static RecurrenceInterval fromName(String? name) {
    if (name == null) return RecurrenceInterval.unknown;
    return RecurrenceInterval.values.firstWhere(
      (i) => i.name == name,
      orElse: () => RecurrenceInterval.unknown,
    );
  }

  String get label {
    switch (this) {
      case RecurrenceInterval.daily:
        return 'Daily';
      case RecurrenceInterval.weekly:
        return 'Weekly';
      case RecurrenceInterval.monthly:
        return 'Monthly';
      case RecurrenceInterval.quarterly:
        return 'Quarterly';
      case RecurrenceInterval.yearly:
        return 'Yearly';
      case RecurrenceInterval.custom:
        return 'Custom';
      case RecurrenceInterval.unknown:
        return 'Not recurring (yet)';
    }
  }
}

/// The recurrence read for one [FinancialObligation] "family" (the same
/// merchant/provider + obligation type observed across possibly many SMS
/// over time) — never declared recurring from a single observation.
class ObligationRecurrence {
  const ObligationRecurrence({
    required this.interval,
    required this.occurrenceCount,
    required this.observedDates,
    required this.confidence,
    this.estimatedIntervalDays,
    this.lastOccurrence,
    this.nextExpectedOccurrence,
  });

  /// A single, freshly-observed occurrence — not yet enough evidence to
  /// call it recurring (see [isConfirmedRecurring]).
  ObligationRecurrence.singleObservation(DateTime observedAt)
    : interval = RecurrenceInterval.unknown,
      occurrenceCount = 1,
      observedDates = [observedAt],
      confidence = 0.0,
      estimatedIntervalDays = null,
      lastOccurrence = observedAt,
      nextExpectedOccurrence = null;

  final RecurrenceInterval interval;
  final int occurrenceCount;
  final List<DateTime> observedDates;

  /// 0.0-1.0. Grows with occurrence count and gap consistency; stays 0.0
  /// until at least two observations exist.
  final double confidence;

  final int? estimatedIntervalDays;
  final DateTime? lastOccurrence;
  final DateTime? nextExpectedOccurrence;

  /// Requires at least two observed occurrences AND a resolved interval —
  /// the hard gate Safety rule 15 exists to enforce.
  bool get isConfirmedRecurring =>
      occurrenceCount >= 2 && interval != RecurrenceInterval.unknown;
}

/// Folds newly observed occurrence dates into an [ObligationRecurrence]
/// read, requiring multiple observations before ever naming a concrete
/// [RecurrenceInterval] — see Safety rule 15.
class ObligationRecurrenceTracker {
  const ObligationRecurrenceTracker();

  ObligationRecurrence observe(
    ObligationRecurrence existing,
    DateTime occurrenceDate,
  ) {
    final dates = [...existing.observedDates, occurrenceDate]..sort();
    if (dates.length < 2) {
      return ObligationRecurrence(
        interval: RecurrenceInterval.unknown,
        occurrenceCount: dates.length,
        observedDates: dates,
        confidence: 0.0,
        lastOccurrence: dates.last,
      );
    }

    final gaps = <int>[];
    for (var i = 1; i < dates.length; i++) {
      gaps.add(dates[i].difference(dates[i - 1]).inDays);
    }
    final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
    final interval = _intervalForGap(avgGap);

    final avgDeviation =
        gaps.map((g) => (g - avgGap).abs()).reduce((a, b) => a + b) /
        gaps.length;
    final consistency = avgGap == 0
        ? 1.0
        : (1 - (avgDeviation / avgGap)).clamp(0.0, 1.0);
    final observationFactor = (0.3 + 0.15 * (dates.length - 2)).clamp(0.0, 0.9);
    final confidence = observationFactor * consistency;

    return ObligationRecurrence(
      interval: interval,
      occurrenceCount: dates.length,
      observedDates: dates,
      confidence: confidence,
      estimatedIntervalDays: avgGap.round(),
      lastOccurrence: dates.last,
      nextExpectedOccurrence: dates.last.add(Duration(days: avgGap.round())),
    );
  }

  RecurrenceInterval _intervalForGap(double days) {
    if (days <= 2) return RecurrenceInterval.daily;
    if (days <= 10) return RecurrenceInterval.weekly;
    if (days <= 45) return RecurrenceInterval.monthly;
    if (days <= 120) return RecurrenceInterval.quarterly;
    if (days <= 400) return RecurrenceInterval.yearly;
    return RecurrenceInterval.custom;
  }
}
