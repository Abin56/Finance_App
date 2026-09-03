/// One structured, privacy-safe historical data point `RecurringPatternDetector`
/// reads from — never the raw SMS, just the fields already resolved
/// elsewhere in this feature.
class MerchantTransactionRecord {
  const MerchantTransactionRecord({
    required this.merchantKey,
    required this.amount,
    required this.date,
  });

  final String merchantKey;
  final double amount;
  final DateTime date;
}

/// A detected repeating merchant+amount+interval pattern — read-only
/// intelligence about the past. Deliberately carries no notion of "next due
/// date," reminder, or transaction: turning this into a reminder/obligation
/// is `ObligationBuilder`'s job (a different, existing subsystem with its own
/// review flow), not this layer's.
class RecurringPattern {
  const RecurringPattern({
    required this.merchantKey,
    required this.amount,
    required this.intervalDays,
    required this.occurrences,
    required this.lastDate,
  });

  final String merchantKey;
  final double amount;
  final int intervalDays;
  final int occurrences;
  final DateTime lastDate;
}

/// Detects merchants charged a roughly-constant amount at a roughly-constant
/// interval — e.g. a ₹199 OTT subscription every ~30 days. Purely
/// observational: it only reports what already happened, never predicts,
/// schedules, or creates anything.
abstract class RecurringPatternDetector {
  RecurringPatternDetector._();

  static List<RecurringPattern> detect(
    List<MerchantTransactionRecord> records, {
    int minOccurrences = 3,
    double amountTolerance = 0.02,
    int intervalToleranceDays = 3,
  }) {
    final byMerchant = <String, List<MerchantTransactionRecord>>{};
    for (final record in records) {
      byMerchant.putIfAbsent(record.merchantKey, () => []).add(record);
    }

    final patterns = <RecurringPattern>[];
    for (final entry in byMerchant.entries) {
      final sorted = List<MerchantTransactionRecord>.of(entry.value)
        ..sort((a, b) => a.date.compareTo(b.date));

      for (final group in _groupByAmount(sorted, amountTolerance)) {
        if (group.length < minOccurrences) continue;

        final intervals = <int>[
          for (var i = 1; i < group.length; i++)
            group[i].date.difference(group[i - 1].date).inDays,
        ];
        final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
        final isConsistent = intervals.every(
          (days) => (days - avgInterval).abs() <= intervalToleranceDays,
        );
        if (!isConsistent) continue;

        patterns.add(
          RecurringPattern(
            merchantKey: entry.key,
            amount: group.last.amount,
            intervalDays: avgInterval.round(),
            occurrences: group.length,
            lastDate: group.last.date,
          ),
        );
      }
    }
    return patterns;
  }

  static List<List<MerchantTransactionRecord>> _groupByAmount(
    List<MerchantTransactionRecord> sorted,
    double amountTolerance,
  ) {
    final groups = <List<MerchantTransactionRecord>>[];
    for (final record in sorted) {
      final group = groups.cast<List<MerchantTransactionRecord>?>().firstWhere(
        (g) =>
            (g!.first.amount - record.amount).abs() <=
            g.first.amount * amountTolerance,
        orElse: () => null,
      );
      if (group != null) {
        group.add(record);
      } else {
        groups.add([record]);
      }
    }
    return groups;
  }
}
