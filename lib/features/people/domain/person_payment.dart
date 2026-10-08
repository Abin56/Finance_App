/// Record Payment allocation — Dart port of the web app's
/// `lib/engines/person-payment.ts`. The Record Payment sheet shows exactly what
/// [allocatePayment] returns and `PersonPaymentRepository` writes exactly those
/// lines; the UI never does its own sums.
///
///  - One payment has one direction: they paid me, or I paid them.
///  - Automatic allocation fills the selected obligations oldest first (date,
///    then when recorded, then key).
///  - Manual allocation: a line can never exceed what is outstanding on it.
///  - Whatever exceeds the allocation is [PaymentAllocation.extra] — never
///    silently classified; it must be kept as advance or recorded as income
///    (or the user selects another obligation).
library;

const double paymentEpsilon = 0.005;

double round2(double v) => (v * 100).roundToDouble() / 100;

enum PaymentDirection { theyPaid, iPaid }

/// theyOwe: they owe me; iOwe: I owe them.
enum ObligationSide { theyOwe, iOwe }

ObligationSide sideForDirection(PaymentDirection d) =>
    d == PaymentDirection.theyPaid ? ObligationSide.theyOwe : ObligationSide.iOwe;

class PaymentObligation {
  const PaymentObligation({
    required this.key,
    required this.title,
    required this.date,
    required this.createdAt,
    required this.amount,
    required this.outstanding,
    required this.side,
  });
  final String key;
  final String title;
  final DateTime date;
  final DateTime createdAt;
  final double amount;
  final double outstanding;
  final ObligationSide side;
}

int compareOldestFirst(PaymentObligation a, PaymentObligation b) {
  var c = a.date.compareTo(b.date);
  if (c != 0) return c;
  c = a.createdAt.compareTo(b.createdAt);
  if (c != 0) return c;
  return a.key.compareTo(b.key);
}

class AllocationLine {
  const AllocationLine(this.key, this.amount, this.outstanding, this.remainingAfter);
  final String key;
  final double amount;
  final double outstanding;
  final double remainingAfter;
}

enum PaymentOutcome { none, full, partial, over }

class PaymentAllocation {
  const PaymentAllocation({
    required this.lines,
    required this.selectedTotal,
    required this.allocated,
    required this.extra,
    required this.unpaid,
    required this.outcome,
    this.error,
  });
  final List<AllocationLine> lines;
  final double selectedTotal;
  final double allocated;
  final double extra;
  final double unpaid;
  final PaymentOutcome outcome;
  final String? error;
}

PaymentAllocation allocatePayment({
  required List<PaymentObligation> obligations,
  required Iterable<String> selectedKeys,
  required double amount,
  Map<String, double>? manual,
}) {
  final selected = selectedKeys.toSet();
  final chosen = obligations.where((o) => selected.contains(o.key) && o.outstanding > paymentEpsilon).toList()
    ..sort(compareOldestFirst);
  final selectedTotal = round2(chosen.fold(0.0, (s, o) => s + o.outstanding));
  final pay = amount.isFinite && amount > 0 ? round2(amount) : 0.0;

  String? error;
  if (chosen.map((o) => o.side).toSet().length > 1) {
    error = 'A payment can only settle one side — what they owe you, or what you owe them.';
  }
  final lines = <AllocationLine>[];
  if (manual != null) {
    for (final o in chosen) {
      final raw = manual[o.key];
      final value = raw == null || !raw.isFinite ? 0.0 : round2(raw);
      if (value < 0) error ??= "Amounts can't be negative.";
      if (value > o.outstanding + paymentEpsilon) {
        error ??= '${o.title}: more than the ${o.outstanding.toStringAsFixed(2)} outstanding.';
      }
      if (value > paymentEpsilon) {
        final rem = round2(o.outstanding - value);
        lines.add(AllocationLine(o.key, value, o.outstanding, rem < 0 ? 0 : rem));
      }
    }
  } else {
    var left = pay;
    for (final o in chosen) {
      if (left <= paymentEpsilon) break;
      final portion = round2(o.outstanding < left ? o.outstanding : left);
      lines.add(AllocationLine(o.key, portion, o.outstanding, round2(o.outstanding - portion)));
      left = round2(left - portion);
    }
  }
  final allocated = round2(lines.fold(0.0, (s, l) => s + l.amount));
  if (allocated > pay + paymentEpsilon) error ??= 'The allocation is more than the payment.';
  final extra = round2(pay - allocated < 0 ? 0 : pay - allocated);
  final unpaid = round2(selectedTotal - allocated < 0 ? 0 : selectedTotal - allocated);
  final outcome = pay <= paymentEpsilon
      ? PaymentOutcome.none
      : extra > paymentEpsilon
          ? PaymentOutcome.over
          : unpaid > paymentEpsilon
              ? PaymentOutcome.partial
              : PaymentOutcome.full;
  return PaymentAllocation(
    lines: lines,
    selectedTotal: selectedTotal,
    allocated: allocated,
    extra: extra,
    unpaid: unpaid,
    outcome: outcome,
    error: error,
  );
}

/// What the extra amount is. "Apply to another obligation" = select it.
sealed class ExtraResolution {
  const ExtraResolution();
}

class KeepAsAdvance extends ExtraResolution {
  const KeepAsAdvance();
}

class RecordAsIncome extends ExtraResolution {
  const RecordAsIncome({required this.categoryId, required this.description});
  final String categoryId;
  final String description;
}

String? paymentBlocker({
  required PaymentDirection direction,
  required double amount,
  required PaymentAllocation allocation,
  required ExtraResolution? resolution,
  required String? accountId,
}) {
  if (!(amount > 0)) return 'Enter the amount.';
  if (allocation.error != null) return allocation.error;
  if (accountId == null || accountId.isEmpty) {
    return direction == PaymentDirection.theyPaid
        ? 'Choose the account it was received into.'
        : 'Choose the account it was paid from.';
  }
  if (allocation.extra > paymentEpsilon) {
    if (resolution == null) return 'Choose what the extra amount is for.';
    if (resolution is RecordAsIncome) {
      if (direction != PaymentDirection.theyPaid) return 'Only money received can be recorded as income.';
      if (resolution.categoryId.isEmpty) return 'Choose an income category.';
    }
  }
  if (allocation.lines.isEmpty && !(allocation.extra > paymentEpsilon && resolution is KeepAsAdvance)) {
    return 'Select what this payment is for.';
  }
  return null;
}

// --- Advance -----------------------------------------------------------------

class AdvanceSource {
  const AdvanceSource({
    required this.entryId,
    required this.date,
    required this.createdAt,
    required this.amount,
    required this.side,
    this.remaining = 0,
  });
  final String entryId;
  final DateTime date;
  final DateTime createdAt;
  final double amount;
  final ObligationSide side;
  final double remaining;
}

class AdvanceUse {
  const AdvanceUse(this.advanceEntryId, this.amount);
  final String advanceEntryId;
  final double amount;
}

List<AdvanceSource> advanceRemaining(
  List<AdvanceSource> advances,
  List<({String advanceEntryId, double amount, bool deleted})> applications,
) {
  final used = <String, double>{};
  for (final a in applications) {
    if (!a.deleted) used[a.advanceEntryId] = round2((used[a.advanceEntryId] ?? 0) + a.amount);
  }
  final sorted = [...advances]..sort((a, b) {
      var c = a.date.compareTo(b.date);
      if (c != 0) return c;
      c = a.createdAt.compareTo(b.createdAt);
      return c != 0 ? c : a.entryId.compareTo(b.entryId);
    });
  return [
    for (final a in sorted)
      AdvanceSource(
        entryId: a.entryId,
        date: a.date,
        createdAt: a.createdAt,
        amount: a.amount,
        side: a.side,
        remaining: round2((a.amount - (used[a.entryId] ?? 0)).clamp(0, double.infinity).toDouble()),
      ),
  ];
}

/// Draws [amount] of advance for [side], oldest advance first. Throws when not enough.
List<AdvanceUse> drawAdvance(List<AdvanceSource> available, ObligationSide side, double amount) {
  var left = round2(amount);
  final uses = <AdvanceUse>[];
  for (final a in available) {
    if (left <= paymentEpsilon) break;
    if (a.side != side || a.remaining <= paymentEpsilon) continue;
    final take = round2(a.remaining < left ? a.remaining : left);
    uses.add(AdvanceUse(a.entryId, take));
    left = round2(left - take);
  }
  if (left > paymentEpsilon) throw StateError('Not enough advance available.');
  return uses;
}
