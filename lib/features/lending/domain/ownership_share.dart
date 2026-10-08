/// Debt ownership — who a Loan/EMI economically belongs to, separate from who
/// the lender holds liable (always me). Port of the web app's
/// `lib/engines/debt-ownership.ts` (accounting rule, not implementation).
///
/// `ownershipShares` (written by Web) fix each party's share of the PRINCIPAL
/// at creation (`personId: null` = me). Every installment is split by those
/// same weights, paise-exact, so the parts always add back to the installment.
/// Legacy documents have no shares: `beneficiaryPersonId` + the explicit
/// `beneficiaryRepaysInstallments` opt-in → 100% that person; else 100% me.
///
/// Flutter has no UI to create shares yet, but MUST carry them through: every
/// Loan/EMI repository write here is a whole-document `set`, so a model that
/// drops the field erases the Web user's shared ownership (and with it every
/// person's installment obligation) on any Flutter close / edit / payment.
library;

class OwnershipShare {
  const OwnershipShare({required this.personId, required this.amount});

  /// null = me (the account owner).
  final String? personId;

  /// This party's share of the principal, in rupees.
  final double amount;

  Map<String, dynamic> toMap() => {'personId': personId, 'amount': amount};
}

/// Exactly Web's `ownershipSharesFromData`: any malformed element → null
/// (treated as a legacy document), never a partial list.
List<OwnershipShare>? ownershipSharesFromData(Object? value) {
  if (value is! List || value.isEmpty) return null;
  final shares = <OwnershipShare>[];
  for (final v in value) {
    if (v is! Map) return null;
    final personId = v['personId'];
    final amount = v['amount'];
    if (amount is! num || !(personId == null || personId is String)) {
      return null;
    }
    shares.add(OwnershipShare(personId: personId as String?, amount: amount.toDouble()));
  }
  return shares;
}

/// Firestore value for [shares] — omitted (null) when there are none, as Web.
List<Map<String, dynamic>>? ownershipSharesToData(List<OwnershipShare>? shares) =>
    shares == null || shares.isEmpty ? null : [for (final s in shares) s.toMap()];

int _toPaise(double v) => (v * 100).round();

/// Split [totalPaise] by [weights] — exact; remainders by largest fractional
/// part, ties by row order (identical to Web `splitPaise`).
List<int> splitPaise(int totalPaise, List<double> weights) {
  if (weights.isEmpty) return const [];
  final sum = weights.fold<double>(0, (s, w) => s + (w > 0 ? w : 0));
  if (sum <= 0) return [for (var i = 0; i < weights.length; i++) i == 0 ? totalPaise : 0];
  final raw = [for (final w in weights) totalPaise * (w > 0 ? w : 0) / sum];
  final floors = [for (final r in raw) r.floor()];
  var left = totalPaise - floors.fold<int>(0, (s, f) => s + f);
  final order = [
    for (var i = 0; i < raw.length; i++)
      if (weights[i] > 0) (i: i, frac: raw[i] - raw[i].floor()),
  ]..sort((a, b) {
      final byFrac = b.frac.compareTo(a.frac);
      return byFrac != 0 ? byFrac : a.i.compareTo(b.i);
    });
  for (var k = 0; left > 0 && order.isNotEmpty; k = (k + 1) % order.length, left--) {
    floors[order[k].i] += 1;
  }
  return floors;
}

bool hasOwnershipShares(List<OwnershipShare>? shares) => (shares?.length ?? 0) > 0;

/// True when [personId] repays me a share of this source's installments.
bool personSharesInstallments({
  required List<OwnershipShare>? ownershipShares,
  required String? beneficiaryPersonId,
  required bool beneficiaryRepaysInstallments,
  required bool isDeleted,
  required String personId,
}) {
  if (isDeleted) return false;
  if (hasOwnershipShares(ownershipShares)) {
    return ownershipShares!.any((s) => s.personId == personId && s.amount > 0);
  }
  return beneficiaryPersonId == personId && beneficiaryRepaysInstallments;
}

/// [personId]'s part of one installment amount under this ownership (0 if none).
double personInstallmentShare({
  required List<OwnershipShare>? ownershipShares,
  required String? beneficiaryPersonId,
  required bool beneficiaryRepaysInstallments,
  required double installmentAmount,
  required String personId,
}) {
  if (!hasOwnershipShares(ownershipShares)) {
    return beneficiaryPersonId == personId && beneficiaryRepaysInstallments ? installmentAmount : 0;
  }
  final parts = splitPaise(_toPaise(installmentAmount), [for (final s in ownershipShares!) _toPaise(s.amount).toDouble()]);
  for (var i = 0; i < ownershipShares.length; i++) {
    if (ownershipShares[i].personId == personId) return parts[i] / 100;
  }
  return 0;
}
