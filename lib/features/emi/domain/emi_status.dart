import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// An [Emi]'s current standing — never stored, always derived (see
/// `Emi.statusGiven`), mirroring `LoanStatus`/`Bill.status` being derived
/// rather than persisted.
///
/// [completed] is distinct from [closed]: it's auto-derived the moment every
/// installment is paid off, while [closed] only ever happens via the
/// explicit "Close EMI" user action (see `Emi.isClosed`). A fully-paid EMI
/// the user hasn't tapped "Close" on reads [completed], not [active].
enum EmiStatus { active, completed, overdue, defaulted, closed }

extension EmiStatusX on EmiStatus {
  String get label {
    switch (this) {
      case EmiStatus.active:
        return 'Active';
      case EmiStatus.completed:
        return 'Completed';
      case EmiStatus.closed:
        return 'Closed';
      case EmiStatus.overdue:
        return 'Missed Payment';
      case EmiStatus.defaulted:
        return 'Defaulted';
    }
  }

  Color get color {
    switch (this) {
      case EmiStatus.active:
        return AppColors.info;
      case EmiStatus.completed:
        return AppColors.success;
      case EmiStatus.closed:
        return AppColors.success;
      case EmiStatus.overdue:
        return AppColors.error;
      case EmiStatus.defaulted:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (this) {
      case EmiStatus.active:
        return Icons.hourglass_top_rounded;
      case EmiStatus.completed:
        return Icons.task_alt_rounded;
      case EmiStatus.closed:
        return Icons.check_circle_outline_rounded;
      case EmiStatus.overdue:
        return Icons.error_outline_rounded;
      case EmiStatus.defaulted:
        return Icons.warning_amber_rounded;
    }
  }
}
