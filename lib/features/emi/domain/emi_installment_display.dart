import '../../../core/extensions/date_extensions.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';

/// Presentation-only relabeling of [InstallmentStatus] for EMI's monthly
/// tracking view. The shared engine has no separate "Unpaid" status (see
/// `InstallmentStatus`) — an [InstallmentStatus.upcoming] installment whose
/// due date falls within the current calendar month reads better to a user
/// as "Unpaid" than "Upcoming"; every other month it stays "Upcoming". No
/// change to the underlying enum or its derivation.
String emiInstallmentStatusLabel(InstallmentStatus status, DateTime dueDate) {
  if (status == InstallmentStatus.upcoming && dueDate.isSameMonth(DateTime.now())) {
    return 'Unpaid';
  }
  return status.label;
}
