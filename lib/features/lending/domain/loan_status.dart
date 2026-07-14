import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// A [Loan]'s current standing — never stored, always derived (see
/// `Loan.statusGiven`), mirroring `BillStatus`/`Person.isCreditor` being
/// derived rather than persisted.
enum LoanStatus { active, closed, overdue }

extension LoanStatusX on LoanStatus {
  String get label {
    switch (this) {
      case LoanStatus.active:
        return 'Active';
      case LoanStatus.closed:
        return 'Closed';
      case LoanStatus.overdue:
        return 'Missed Payment';
    }
  }

  Color get color {
    switch (this) {
      case LoanStatus.active:
        return AppColors.info;
      case LoanStatus.closed:
        return AppColors.success;
      case LoanStatus.overdue:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (this) {
      case LoanStatus.active:
        return Icons.hourglass_top_rounded;
      case LoanStatus.closed:
        return Icons.check_circle_outline_rounded;
      case LoanStatus.overdue:
        return Icons.error_outline_rounded;
    }
  }
}
