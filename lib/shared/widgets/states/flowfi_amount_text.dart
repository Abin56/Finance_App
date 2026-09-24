import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';

/// A financial amount's font size/weight role — the number's job on screen
/// determines its style, not which widget happens to render it. See
/// [FlowFiAmountText].
enum AmountSize {
  /// The single largest number on a screen — a hero card's total balance.
  display,

  /// A summary card's own balance/total — prominent, but not the page's
  /// single focal point.
  large,

  /// A compact statistic (a stat tile, a quick-glance figure).
  statistic,

  /// An amount inline in a list row (a transaction's signed value).
  body,
}

/// The "large financial numbers as the focal point" primitive — tabular
/// figures so digits don't jiggle, weight/size driven by [AmountSize], and
/// an optional semantic color for credit/debit rows. Every screen showing a
/// balance, total, or transaction amount should render it through this
/// rather than a bare [Text] with ad-hoc styling, so amounts look consistent
/// app-wide.
class FlowFiAmountText extends StatelessWidget {
  const FlowFiAmountText(
    this.value, {
    super.key,
    this.size = AmountSize.body,
    this.color,
    this.prefix,
    this.maxLines,
    this.overflow,
  });

  final String value;
  final AmountSize size;

  /// Overrides the default text color (e.g. income green / expense red).
  /// Defaults to the ambient text color when null.
  final Color? color;

  /// An optional leading glyph rendered at a lighter weight than [value]
  /// (e.g. a "+"/"-" sign) — kept separate so the sign doesn't inherit the
  /// same bold tabular styling as the digits.
  final String? prefix;

  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    final style = switch (size) {
      AmountSize.display => textTheme.displayLarge,
      AmountSize.large => textTheme.headlineLarge,
      AmountSize.statistic => textTheme.titleLarge,
      AmountSize.body => textTheme.titleMedium,
    };

    final resolved = style?.copyWith(color: color);

    if (prefix == null) {
      return Text(
        value,
        style: resolved,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: resolved,
        children: [
          TextSpan(
            text: prefix,
            style: resolved?.copyWith(fontWeight: FontWeight.w500),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
