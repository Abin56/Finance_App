import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../../shared/widgets/states/payment_urgency_badge.dart';
import '../../../categories/domain/category.dart';
import '../../domain/bill.dart';
import '../../domain/bill_occurrence.dart';
import '../../domain/bill_status.dart';

/// Row for a single bill — status-colored icon, name, due-date/category
/// subtitle, remaining amount, and a status badge. Swipeable to
/// soft-delete, handled by the screen that owns the Dismissible key.
/// [occurrence] is the bill's current occurrence (null only if it hasn't
/// been materialized yet, momentarily, before
/// `materializeBillOccurrenceProvider` first resolves).
class BillTile extends StatelessWidget {
  const BillTile({
    super.key,
    required this.bill,
    required this.occurrence,
    required this.category,
    required this.onTap,
  });

  final Bill bill;
  final BillOccurrence? occurrence;
  final Category? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occurrence = this.occurrence;
    if (occurrence == null) return const SizedBox.shrink();
    final status = occurrence.status;
    final urgency = PaymentUrgencyX.fromBillStatus(status);
    final subtitleParts = [
      occurrence.dueDate.shortDate,
      if (category != null) category!.name,
    ];

    return FlowFiCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: FlowFiListTile(
        leading: FlowFiIconChip(
          icon: status.icon,
          color: status.color,
          size: 44,
        ),
        title: Text(
          bill.name,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitleParts.join(' · '),
          style: context.textTheme.bodySmall?.copyWith(
            color: context.flowfi.textTertiary,
          ),
        ),
        trailing: FlowFiAmountText(
          CurrencyFormatter.instance.format(occurrence.remainingAmount),
          size: AmountSize.body,
        ),
        trailingSubtitle: PaymentUrgencyBadge(urgency: urgency, compact: true),
      ),
    );
  }
}
