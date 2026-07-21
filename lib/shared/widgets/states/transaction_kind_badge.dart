import 'package:flutter/material.dart';

import '../../domain/transaction_kind.dart';

/// A small tinted pill combining [TransactionKind.icon]/[TransactionKindX.label]/
/// [TransactionKindX.color] — the one widget every history-style row in the
/// app (Main History, Person Statement, Loan/EMI/Bill/Credit Card
/// timelines, Search results, Dashboard recent activity) should render, so
/// "what kind of money movement is this" always looks identical no matter
/// which screen it's on. Mirrors [MoneyDirectionBadge]'s shape exactly
/// (tinted `Container` + icon + label, a `compact` variant for dense rows)
/// rather than inventing a second badge convention.
///
/// Colors come from [TransactionKind.color], which is theme-independent —
/// tinted at low alpha over whatever surface it sits on, so it reads
/// correctly in both light and dark mode without a separate dark palette.
/// Text uses the ambient [Theme]'s text styles, which already scale with
/// the platform's accessibility text-size setting; nothing here hardcodes
/// a font size.
class TransactionKindBadge extends StatelessWidget {
  const TransactionKindBadge({super.key, required this.kind, this.compact = false});

  final TransactionKind kind;

  /// Smaller padding/text/icon for dense rows (e.g. inline in a list tile)
  /// instead of a standalone card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = kind.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kind.icon, size: compact ? 12 : 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              kind.label,
              style: (compact ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
