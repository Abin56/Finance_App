import '../../../core/extensions/date_extensions.dart';
import '../../reports/domain/reports_period.dart';
import 'cash_flow_period.dart';

export 'cash_flow_period.dart' show CashFlowPreset, CashFlowPresetX;

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
