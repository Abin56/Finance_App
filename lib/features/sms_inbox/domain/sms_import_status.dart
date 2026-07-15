import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Where a detected SMS sits in the manual-review pipeline. An SMS never
/// moves past [pending] on its own — only a user action (`Convert` or
/// `Ignore`) transitions it, and only [imported] items are linked to a real
/// FlowFi record. See `SmsInboxRepository` for the transition methods.
enum SmsImportStatus { pending, imported, ignored }

extension SmsImportStatusX on SmsImportStatus {
  static SmsImportStatus fromName(String name) =>
      SmsImportStatus.values.firstWhere((s) => s.name == name, orElse: () => SmsImportStatus.pending);

  String get label {
    switch (this) {
      case SmsImportStatus.pending:
        return 'Pending review';
      case SmsImportStatus.imported:
        return 'Already imported';
      case SmsImportStatus.ignored:
        return 'Ignored';
    }
  }

  IconData get icon {
    switch (this) {
      case SmsImportStatus.pending:
        return Icons.hourglass_top_rounded;
      case SmsImportStatus.imported:
        return Icons.check_circle_rounded;
      case SmsImportStatus.ignored:
        return Icons.visibility_off_rounded;
    }
  }

  Color get color {
    switch (this) {
      case SmsImportStatus.pending:
        return AppColors.pending;
      case SmsImportStatus.imported:
        return AppColors.success;
      case SmsImportStatus.ignored:
        return AppColors.lightTextSecondary;
    }
  }
}
