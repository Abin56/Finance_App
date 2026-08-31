import 'package:flutter/material.dart';

/// Animates a numeric value counting up from its previous value to [value]
/// whenever it changes — used for balance/total displays so updates feel
/// alive instead of just snapping to a new number.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  final double value;
  final String Function(double value) formatter;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Tabular figures so digits don't shift width as the count-up animates —
    // matches the web app's `tabular-nums` on every currency figure.
    final tabularStyle = (style ?? const TextStyle()).copyWith(
      fontFeatures: [const FontFeature.tabularFigures()],
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) => Text(formatter(animatedValue), style: tabularStyle),
    );
  }
}
