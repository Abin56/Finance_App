import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// A credit card's lifecycle state. [active] is the normal, in-use card;
/// [closed] and [cancelled] both mean the card is no longer usable (kept
/// separate only so the user can record which happened) — see
/// [CreditCardStatusX.isActive] for the "can still be used" check every
/// screen should branch on rather than testing the enum values directly.
enum CreditCardStatus { active, blocked, closed, cancelled }

extension CreditCardStatusX on CreditCardStatus {
  static CreditCardStatus fromName(String name) =>
      CreditCardStatus.values.firstWhere((s) => s.name == name, orElse: () => CreditCardStatus.active);

  String get label {
    switch (this) {
      case CreditCardStatus.active:
        return 'Active';
      case CreditCardStatus.blocked:
        return 'Blocked';
      case CreditCardStatus.closed:
        return 'Closed';
      case CreditCardStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// Whether the card can still be spent on — blocked/closed/cancelled
  /// cards can't, even if they still carry an unpaid balance. [blocked] is
  /// temporary (lost/stolen/frozen) and can be reactivated later, unlike
  /// [closed] (permanent) or [cancelled].
  bool get isActive => this == CreditCardStatus.active;

  Color get color {
    switch (this) {
      case CreditCardStatus.active:
        return AppColors.success;
      case CreditCardStatus.blocked:
        return AppColors.warning;
      case CreditCardStatus.closed:
        return AppColors.pending;
      case CreditCardStatus.cancelled:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (this) {
      case CreditCardStatus.active:
        return Icons.check_circle_outline_rounded;
      case CreditCardStatus.blocked:
        return Icons.block_rounded;
      case CreditCardStatus.closed:
        return Icons.lock_outline_rounded;
      case CreditCardStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }
}
