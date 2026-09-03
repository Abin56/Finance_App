/// Pure calculation for "mixed" expense splitting: some participants have a
/// manually-locked amount, everyone else automatically splits whatever is
/// left of the total equally.
///
/// Kept separate from `ExpenseRepository.resolveShares` (the source of truth
/// for `SplitType.equal`/`custom`/`percentage`/`none`, also ported byte-for-
/// byte to the web app) because this is a form-layer UX convenience — it
/// always resolves down to a plain per-person amount, so the result can be
/// fed straight into `resolveShares(type: SplitType.custom, ...)` with zero
/// changes to persistence or that shared calculation engine.
library;

/// One participant's raw input before a mixed split is resolved.
class MixedParticipantInput {
  const MixedParticipantInput({required this.key, required this.locked, required this.value});

  /// Stable identity for matching a share back to its participant — personId, or name for untracked people.
  final String key;

  /// Manually typed by the user; false means "auto — share of whatever's left".
  final bool locked;

  /// Only meaningful when [locked] is true.
  final double value;
}

class MixedShare {
  const MixedShare({required this.key, required this.share, required this.locked});

  final String key;
  final double share;
  final bool locked;
}

class MixedSplitResult {
  const MixedSplitResult({
    required this.shares,
    required this.lockedTotal,
    required this.remaining,
    required this.autoCount,
    required this.autoShare,
    required this.error,
  });

  final List<MixedShare> shares;
  final double lockedTotal;
  final double remaining;
  final int autoCount;

  /// The even per-person amount before the rounding remainder is applied to the last auto participant.
  final double autoShare;
  final String? error;
}

double _round2(double v) => (v * 100).round() / 100;

/// Formats a rounded amount for an inline error message without a spurious
/// trailing ".0" on whole numbers (Dart's default double->String keeps it).
String _formatAmount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

MixedSplitResult resolveMixedSplit(double total, List<MixedParticipantInput> inputs) {
  final roundedTotal = _round2(total);
  final lockedInputs = inputs.where((i) => i.locked).toList();
  final autoInputs = inputs.where((i) => !i.locked).toList();
  final lockedTotal = _round2(lockedInputs.fold(0.0, (sum, i) => sum + i.value));
  final remaining = _round2(roundedTotal - lockedTotal);

  if (inputs.isEmpty) {
    return MixedSplitResult(shares: const [], lockedTotal: 0, remaining: roundedTotal, autoCount: 0, autoShare: 0, error: null);
  }

  if (lockedTotal > roundedTotal) {
    return MixedSplitResult(
      shares: [for (final i in inputs) MixedShare(key: i.key, share: i.locked ? i.value : 0, locked: i.locked)],
      lockedTotal: lockedTotal,
      remaining: remaining,
      autoCount: autoInputs.length,
      autoShare: 0,
      error: 'Assigned amount exceeds the expense total by ₹${_formatAmount(_round2(lockedTotal - roundedTotal))}',
    );
  }

  if (autoInputs.isEmpty) {
    if (remaining != 0) {
      return MixedSplitResult(
        shares: [for (final i in inputs) MixedShare(key: i.key, share: i.value, locked: i.locked)],
        lockedTotal: lockedTotal,
        remaining: remaining,
        autoCount: 0,
        autoShare: 0,
        error: '₹${_formatAmount(remaining)} is left unassigned — mark a participant as Equal, or adjust an amount',
      );
    }
    return MixedSplitResult(
      shares: [for (final i in inputs) MixedShare(key: i.key, share: i.value, locked: i.locked)],
      lockedTotal: lockedTotal,
      remaining: 0,
      autoCount: 0,
      autoShare: 0,
      error: null,
    );
  }

  final autoShare = _round2(remaining / autoInputs.length);
  final autoRemainder = _round2(remaining - autoShare * autoInputs.length);

  var autoSeen = 0;
  final shares = [
    for (final i in inputs)
      if (i.locked)
        MixedShare(key: i.key, share: i.value, locked: true)
      else
        MixedShare(
          key: i.key,
          share: (++autoSeen == autoInputs.length) ? _round2(autoShare + autoRemainder) : autoShare,
          locked: false,
        ),
  ];

  return MixedSplitResult(
    shares: shares,
    lockedTotal: lockedTotal,
    remaining: remaining,
    autoCount: autoInputs.length,
    autoShare: autoShare,
    error: null,
  );
}
