import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// An [Installment]'s current standing, derived from its due date, amount,
/// amountPaid, and isSkipped flag — never stored, always computed by
/// `Installment.status`, mirroring `BillStatus`/`Bill.status`.
enum InstallmentStatus { paid, partiallyPaid, skipped, overdue, upcoming }

extension InstallmentStatusX on InstallmentStatus {
  String get label {
    switch (this) {
      case InstallmentStatus.paid:
        return 'Paid';
      case InstallmentStatus.partiallyPaid:
        return 'Partially paid';
      case InstallmentStatus.skipped:
        return 'Skipped';
      case InstallmentStatus.overdue:
        return 'Missed Payment';
      case InstallmentStatus.upcoming:
        return 'Upcoming';
    }
  }

  Color get color {
    switch (this) {
      case InstallmentStatus.paid:
        return AppColors.success;
      case InstallmentStatus.partiallyPaid:
        return AppColors.warning;
      case InstallmentStatus.skipped:
        return AppColors.pending;
      case InstallmentStatus.overdue:
        return AppColors.error;
      case InstallmentStatus.upcoming:
        return AppColors.info;
    }
  }

  IconData get icon {
    switch (this) {
      case InstallmentStatus.paid:
        return Icons.check_circle_outline_rounded;
      case InstallmentStatus.partiallyPaid:
        return Icons.incomplete_circle_rounded;
      case InstallmentStatus.skipped:
        return Icons.skip_next_rounded;
      case InstallmentStatus.overdue:
        return Icons.error_outline_rounded;
      case InstallmentStatus.upcoming:
        return Icons.schedule_rounded;
    }
  }
}
