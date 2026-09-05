import '../../../core/extensions/date_extensions.dart';
import '../../reports/domain/reports_period.dart';
import '../../transactions/domain/transaction.dart';

/// Preset choices for the Cash Flow date-range filter — a deliberately
/// small subset of [ReportsPeriod] (no year/financial-year presets; Cash
/// Flow is a near-term planning view, not a yearly report), plus [custom]
/// for a user-picked [DateRange] via `showDateRangePicker`.
enum CashFlowPreset { thisMonth, lastMonth, thisWeek, custom }

extension CashFlowPresetX on CashFlowPreset {
  String get label {
    switch (this) {
      case CashFlowPreset.thisMonth:
        return 'This Month';
      case CashFlowPreset.lastMonth:
        return 'Last Month';
      case CashFlowPreset.thisWeek:
        return 'This Week';
      case CashFlowPreset.custom:
        return 'Custom Range';
    }
  }

  /// Inclusive start/end for this preset, relative to [now]. [custom] has
  /// no inherent range — callers must supply their own picked range and
  /// never call this getter for it, same contract as
  /// `ReportsPeriod.rangeFor`.
  DateRange rangeFor(DateTime now) {
    switch (this) {
      case CashFlowPreset.thisMonth:
        return DateRange(now.startOfMonth, now.endOfMonth);
      case CashFlowPreset.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1);
        return DateRange(lastMonth.startOfMonth, lastMonth.endOfMonth);
      case CashFlowPreset.thisWeek:
        return DateRange(now.startOfWeek, now.endOfWeek);
      case CashFlowPreset.custom:
        throw UnsupportedError('CashFlowPreset.custom has no inherent range');
    }
  }
}

/// The Cash Flow screen's selected date-range filter state — a [preset]
/// (recomputed against "now" on every read, so "This Month" keeps rolling
/// forward across a month boundary without a stale stored range) or a
/// user-picked [CashFlowPreset.custom] range, which is frozen at pick time
/// since there's no "now" to recompute it from.
class CashFlowPeriod {
  const CashFlowPeriod.preset(this.preset) : customRange = null;
  const CashFlowPeriod.custom(DateRange range) : preset = CashFlowPreset.custom, customRange = range;

  final CashFlowPreset preset;
  final DateRange? customRange;

  /// Whether this period is bucketed by whole calendar month —
  /// [Transaction.effectiveMonth] (Accounting Month) only encodes a month,
  /// so it's only a sound bucketing key for a period that's itself a whole
  /// month. [thisWeek] and [custom] (day-precision ranges, potentially as
  /// short as a single day) must instead read the transaction's real
  /// [Transaction.dateTime] — same split Reports' `ReportsPeriod.isMonthGranular`
  /// already makes, for the same reason: bucketing a single-day range by
  /// [Transaction.effectiveMonth] would let every transaction in that whole
  /// month leak through, since [Transaction.effectiveMonth] truncates to the
  /// 1st of the month regardless of which day within it was picked.
  bool get isMonthGranular => preset == CashFlowPreset.thisMonth || preset == CashFlowPreset.lastMonth;

  /// The single date every Cash Flow calculation must bucket [transaction]
  /// under for this period — [Transaction.effectiveMonth] when
  /// [isMonthGranular], else [Transaction.dateTime]. The one place this
  /// decision is made, so every range-aware Cash Flow provider (summary,
  /// Money In/Out details) reaches the same answer for the same transaction.
  DateTime bucketDateFor(Transaction transaction) => isMonthGranular ? transaction.effectiveMonth : transaction.dateTime;

  DateRange rangeFor(DateTime now) => preset == CashFlowPreset.custom ? customRange! : preset.rangeFor(now);

  /// Short label for the filter chip — the preset's own label, or the
  /// picked range formatted as "1 Sep 2026 – 30 Sep 2026" for a custom one.
  String labelFor(DateTime now) {
    if (preset != CashFlowPreset.custom) return preset.label;
    final range = customRange!;
    return '${range.start.fullDate} – ${range.end.fullDate}';
  }
}
