import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// A [Statement]'s current standing, derived from its due date, total, and
/// amountPaid — never stored, always computed by [Statement.status]
/// (mirrors [BillStatus] being computed by [Bill.status]).
enum StatementStatus { paid, partiallyPaid, dueSoon, overdue, pending }

extension StatementStatusX on StatementStatus {
  String get label {
    switch (this) {
      case StatementStatus.paid:
        return 'Paid';
      case StatementStatus.partiallyPaid:
        return 'Partially paid';
      case StatementStatus.dueSoon:
        return 'Due soon';
      case StatementStatus.overdue:
        return 'Overdue';
      case StatementStatus.pending:
        return 'Pending';
    }
  }

  Color get color {
    switch (this) {
      case StatementStatus.paid:
        return AppColors.success;
      case StatementStatus.partiallyPaid:
        return AppColors.warning;
      case StatementStatus.dueSoon:
        return AppColors.warning;
      case StatementStatus.overdue:
        return AppColors.error;
      case StatementStatus.pending:
        return AppColors.info;
    }
  }

  IconData get icon {
    switch (this) {
      case StatementStatus.paid:
        return Icons.check_circle_outline_rounded;
      case StatementStatus.partiallyPaid:
        return Icons.incomplete_circle_rounded;
      case StatementStatus.dueSoon:
        return Icons.today_rounded;
      case StatementStatus.overdue:
        return Icons.error_outline_rounded;
      case StatementStatus.pending:
        return Icons.schedule_rounded;
    }
  }
}
