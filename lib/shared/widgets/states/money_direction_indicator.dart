import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Task 4's "make pending money instantly readable" convention — one shared
/// meaning for every screen that shows money owed between the user and
/// someone else (a [Person], a split expense, a loan): green + down arrow
/// for money coming to the user, red + up arrow for money the user owes,
/// orange for partially settled, and a green check once fully settled. Every
/// screen that shows this kind of status (Person Detail, Person List, Split
/// Expense, History, Dashboard) should derive its color/icon/label from one
/// of these four values rather than hand-rolling its own.
enum MoneyDirection {
  /// Money the user is owed and will receive.
  toReceive,

  /// Money the user owes and must pay.
  toPay,

  /// Partially settled — still has money moving in either direction.
  partial,

  /// Fully settled — nothing outstanding either way.
  completed,
}

extension MoneyDirectionX on MoneyDirection {
  /// Derives the direction from a signed balance — positive means the other
  /// party owes the user (so the user is "to receive"), negative means the
  /// user owes them ("to pay"), matching [Person.currentBalance]'s and
  /// [LedgerEntry.signedAmount]'s sign convention exactly. Returns null for
  /// a zero balance, which is [MoneyDirection.completed] rather than a
  /// direction.
  static MoneyDirection? forSignedBalance(double signedBalance) {
    if (signedBalance > 0) return MoneyDirection.toReceive;
    if (signedBalance < 0) return MoneyDirection.toPay;
    return null;
  }

  String get label {
    switch (this) {
      case MoneyDirection.toReceive:
        return 'To Receive';
      case MoneyDirection.toPay:
        return 'To Pay';
      case MoneyDirection.partial:
        return 'Partly Paid';
      case MoneyDirection.completed:
        return 'Paid';
    }
  }

  Color get color {
    switch (this) {
      case MoneyDirection.toReceive:
        return AppColors.success;
      case MoneyDirection.toPay:
        return AppColors.error;
      case MoneyDirection.partial:
        return AppColors.warning;
      case MoneyDirection.completed:
        return AppColors.success;
    }
  }

  IconData get icon {
    switch (this) {
      case MoneyDirection.toReceive:
        return Icons.arrow_downward_rounded;
      case MoneyDirection.toPay:
        return Icons.arrow_upward_rounded;
      case MoneyDirection.partial:
        return Icons.incomplete_circle_rounded;
      case MoneyDirection.completed:
        return Icons.check_circle_rounded;
    }
  }
}

/// A small tinted pill combining [MoneyDirection.icon]/[label]/[color] —
/// the one widget every "pending money" surface in the app should render,
/// so a "To Receive"/"To Pay"/"Partial"/"Completed" badge always looks
/// identical no matter which screen it's on.
class MoneyDirectionBadge extends StatelessWidget {
  const MoneyDirectionBadge({super.key, required this.direction, this.compact = false});

  final MoneyDirection direction;

  /// Smaller padding/text for dense rows (e.g. inline in a list tile)
  /// instead of a standalone card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = direction.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(direction.icon, size: compact ? 12 : 16, color: color),
          const SizedBox(width: 4),
          Text(
            direction.label,
            style: (compact ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
