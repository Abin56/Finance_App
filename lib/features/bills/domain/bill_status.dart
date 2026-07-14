import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// A [Bill]'s current standing, derived from its due date, amount,
/// amountPaid, and isSkipped flag — never stored, always computed by
/// [Bill.status] (mirrors [Person.isCreditor]/[isDebtor] being derived
/// from balance sign rather than persisted).
enum BillStatus { paid, partiallyPaid, skipped, overdue, dueToday, upcoming }

extension BillStatusX on BillStatus {
  String get label {
    switch (this) {
      case BillStatus.paid:
        return 'Paid';
      case BillStatus.partiallyPaid:
        return 'Partially paid';
      case BillStatus.skipped:
        return 'Skipped';
      case BillStatus.overdue:
        return 'Missed Payment';
      case BillStatus.dueToday:
        return 'Due today';
      case BillStatus.upcoming:
        return 'Upcoming';
    }
  }

  Color get color {
    switch (this) {
      case BillStatus.paid:
        return AppColors.success;
      case BillStatus.partiallyPaid:
        return AppColors.warning;
      case BillStatus.skipped:
        return AppColors.pending;
      case BillStatus.overdue:
        return AppColors.error;
      case BillStatus.dueToday:
        return AppColors.warning;
      case BillStatus.upcoming:
        return AppColors.info;
    }
  }

  IconData get icon {
    switch (this) {
      case BillStatus.paid:
        return Icons.check_circle_outline_rounded;
      case BillStatus.partiallyPaid:
        return Icons.incomplete_circle_rounded;
      case BillStatus.skipped:
        return Icons.skip_next_rounded;
      case BillStatus.overdue:
        return Icons.error_outline_rounded;
      case BillStatus.dueToday:
        return Icons.today_rounded;
      case BillStatus.upcoming:
        return Icons.schedule_rounded;
    }
  }
}
