import 'learning_source.dart';

/// One recorded sighting of a value for a merchant field — a confirmation of
/// an existing value, or an explicit correction to a new one. Full history
/// is always preserved by the caller (see `MerchantCorrectionLog`); this
/// class only carries what `MerchantPreferenceResolver` needs to pick a
/// winner, it is never itself the store of record.
class MerchantFieldObservation<T> {
  const MerchantFieldObservation({
    required this.value,
    required this.timestamp,
    required this.isCorrection,
    this.source = LearningSource.user,
  });

  final T value;
  final DateTime timestamp;
  final bool isCorrection;
  final LearningSource source;
}

/// The outcome of resolving conflicting history for one field: a preferred
/// value plus why, alongside the untouched observation history that
/// produced it — so a caller (or reviewer) can always see the values this
/// discarded, rather than resolution silently erasing them.
class PreferenceResolution<T> {
  const PreferenceResolution({
    required this.value,
    required this.reason,
    required this.history,
  });

  final T value;
  final String reason;
  final List<MerchantFieldObservation<T>> history;
}

/// Picks the "current preferred" value for a merchant field when history
/// contains more than one distinct value — e.g. a user who filed Amazon
/// under Shopping nine times and Electronics once. Never mutates or drops
/// history; it only ranks it.
///
/// Priority:
///  1. An explicit correction that is the most recent observation of all —
///     the user just told us the current truth, so it wins outright
///     regardless of how much older history disagrees.
///  2. Otherwise, the most frequent value, breaking ties by whichever was
///     seen most recently.
abstract class MerchantPreferenceResolver {
  MerchantPreferenceResolver._();

  static PreferenceResolution<T>? resolve<T>(
    List<MerchantFieldObservation<T>> observations,
  ) {
    if (observations.isEmpty) return null;

    final sorted = List<MerchantFieldObservation<T>>.of(observations)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final mostRecent = sorted.last;
    if (mostRecent.isCorrection) {
      return PreferenceResolution(
        value: mostRecent.value,
        reason: 'explicit user correction',
        history: sorted,
      );
    }

    final counts = <T, int>{};
    final lastSeenAt = <T, DateTime>{};
    for (final observation in sorted) {
      counts[observation.value] = (counts[observation.value] ?? 0) + 1;
      lastSeenAt[observation.value] = observation.timestamp;
    }

    T? winner;
    var bestCount = -1;
    DateTime? bestTime;
    for (final entry in counts.entries) {
      final seenAt = lastSeenAt[entry.key]!;
      final beatsOnCount = entry.value > bestCount;
      final tiesOnCountButNewer =
          entry.value == bestCount && (bestTime == null || seenAt.isAfter(bestTime));
      if (beatsOnCount || tiesOnCountButNewer) {
        winner = entry.key;
        bestCount = entry.value;
        bestTime = seenAt;
      }
    }

    return PreferenceResolution(
      value: winner as T,
      reason: 'most frequent value, most recent as tiebreak',
      history: sorted,
    );
  }
}
