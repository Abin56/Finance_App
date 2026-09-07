import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../domain/payment_record.dart';

/// One entry in a bill's payment timeline.
class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.payment, required this.onTap});

  final PaymentRecord payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FlowFiCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: FlowFiListTile(
        leading: FlowFiIconChip(
          icon: Icons.payments_outlined,
          color: context.colors.primary,
          size: 40,
        ),
        title: Text(
          payment.note.isNotEmpty
              ? '${payment.date.shortDate} · ${payment.note}'
              : payment.date.shortDate,
          style: context.textTheme.bodyMedium,
        ),
        trailing: FlowFiAmountText(
          CurrencyFormatter.instance.format(payment.amount),
          size: AmountSize.body,
        ),
      ),
    );
  }
}
