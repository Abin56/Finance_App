/// Formatting helpers for amounts and percentages.
/// Currency symbol/formatting rules live in `core/utils/currency_formatter.dart`;
/// these extensions cover lightweight numeric helpers used in widgets.
extension NumX on num {
  /// Clamps a ratio (e.g. spent / budget) into a safe 0.0–1.0 range for
  /// progress indicators, avoiding NaN/Infinity when the denominator is 0.
  double get clampedProgress {
    if (isNaN || isInfinite) return 0;
    return clamp(0, 1).toDouble();
  }

  String get asPercent => '${(this * 100).toStringAsFixed(0)}%';
}
