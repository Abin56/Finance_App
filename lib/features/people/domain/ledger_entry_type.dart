import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// The kind of ledger movement recorded against a [Person]. Balance sign
/// convention (positive = they owe you, negative = you owe them):
///
/// | type          | effect on balance |
/// |---------------|--------------------|
/// | gave          | +amount            |
/// | repaid        | +amount            |
/// | borrowed      | -amount            |
/// | receivedBack  | -amount            |
/// | adjustment    | user-signed amount, passed through unchanged |
///
/// "Gave" and "repaid" both push the balance toward "they owe you more";
/// "borrowed" and "receivedBack" both push it toward "you owe them more"
/// (or reduce what they owe you). Do not change this table without
/// updating every dashboard stat that assumes positive = receivable.
enum LedgerEntryType { gave, borrowed, receivedBack, repaid, adjustment }

extension LedgerEntryTypeX on LedgerEntryType {
  static LedgerEntryType fromName(String name) =>
      LedgerEntryType.values.firstWhere((t) => t.name == name, orElse: () => LedgerEntryType.adjustment);

  String get label {
    switch (this) {
      case LedgerEntryType.gave:
        return 'They Need to Pay Me';
      case LedgerEntryType.borrowed:
        return 'They Paid for Me';
      case LedgerEntryType.receivedBack:
        return 'Received Payment';
      case LedgerEntryType.repaid:
        return 'Mark as Paid';
      case LedgerEntryType.adjustment:
        return 'Correct Balance';
    }
  }

  /// A short, plain-language explanation shown under [label] in the entry
  /// type picker — so a user with no accounting background can tell these
  /// five options apart without guessing from the label alone.
  String get description {
    switch (this) {
      case LedgerEntryType.gave:
        return 'I spent money for them, so they owe me back.';
      case LedgerEntryType.borrowed:
        return 'They paid something on my behalf.';
      case LedgerEntryType.receivedBack:
        return 'They returned money to me.';
      case LedgerEntryType.repaid:
        return 'You paid back what you owed them.';
      case LedgerEntryType.adjustment:
        return 'Correct an incorrect balance.';
    }
  }

  IconData get icon {
    switch (this) {
      case LedgerEntryType.gave:
        return Icons.call_made_rounded;
      case LedgerEntryType.borrowed:
        return Icons.call_received_rounded;
      case LedgerEntryType.receivedBack:
        return Icons.undo_rounded;
      case LedgerEntryType.repaid:
        return Icons.redo_rounded;
      case LedgerEntryType.adjustment:
        return Icons.tune_rounded;
    }
  }

  /// Whether the user enters a plain positive [amount] (gave/borrowed/
  /// receivedBack/repaid, direction implied by [type]) or a signed amount
  /// they choose themselves (adjustment — can push the balance either way).
  bool get isSignedByUser => this == LedgerEntryType.adjustment;

  /// Applies this type's sign convention to a positive [amount]. For
  /// [adjustment], [amount] is expected to already carry the user's chosen
  /// sign and is passed through unchanged.
  double signFor(double amount) {
    switch (this) {
      case LedgerEntryType.gave:
      case LedgerEntryType.repaid:
        return amount;
      case LedgerEntryType.borrowed:
      case LedgerEntryType.receivedBack:
        return -amount;
      case LedgerEntryType.adjustment:
        return amount;
    }
  }

  /// User-friendly color, independent of [signFor]'s balance-direction math:
  /// red only for [gave] (an open ask — they haven't paid yet), green for
  /// every entry that represents money actually changing hands ([borrowed],
  /// [receivedBack], [repaid]), and neutral for [adjustment] since it can go
  /// either way.
  Color get color {
    switch (this) {
      case LedgerEntryType.gave:
        return AppColors.debit;
      case LedgerEntryType.borrowed:
      case LedgerEntryType.receivedBack:
      case LedgerEntryType.repaid:
        return AppColors.credit;
      case LedgerEntryType.adjustment:
        return AppColors.pending;
    }
  }
}
