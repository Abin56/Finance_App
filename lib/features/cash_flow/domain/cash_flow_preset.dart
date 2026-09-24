import '../../../core/extensions/date_extensions.dart';
import '../../reports/domain/reports_period.dart';

/// The Cash Flow Center's own period presets, distinct from
/// [ReportsPeriod] (Reports has different options — Today/This Year/
/// Financial Year — that don't fit a forward-looking planning screen).
/// Reuses [DateRange] as the shared "inclusive start/end" shape so range
/// containment logic (`DateRange.contains`) stays in one place.
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
        return 'Custom';
    }
  }

  /// Inclusive start/end for this preset, relative to [now]. [custom] has
  /// no inherent range — callers must supply their own picked range and
  /// never call this getter for it.
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

/// The Cash Flow Center's currently selected period — a [preset] plus the
/// [range] it resolves to (computed once at selection time so the screen
/// doesn't silently drift as "now" changes while it's open).
class CashFlowSelection {
  const CashFlowSelection({required this.preset, required this.range});

  final CashFlowPreset preset;
  final DateRange range;

  factory CashFlowSelection.initial() =>
      CashFlowSelection(preset: CashFlowPreset.thisMonth, range: CashFlowPreset.thisMonth.rangeFor(DateTime.now()));

  String get label {
    if (preset != CashFlowPreset.custom) return preset.label;
    return '${range.start.shortDate} – ${range.end.shortDate}';
  }
}
