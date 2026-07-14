import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// An [Emi]'s current standing — never stored, always derived (see
/// `Emi.statusGiven`), mirroring `LoanStatus`/`Bill.status` being derived
/// rather than persisted.
enum EmiStatus { active, closed, overdue, defaulted }

extension EmiStatusX on EmiStatus {
  String get label {
    switch (this) {
      case EmiStatus.active:
        return 'Active';
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
      case EmiStatus.closed:
        return Icons.check_circle_outline_rounded;
      case EmiStatus.overdue:
        return Icons.error_outline_rounded;
      case EmiStatus.defaulted:
        return Icons.warning_amber_rounded;
    }
  }
}
