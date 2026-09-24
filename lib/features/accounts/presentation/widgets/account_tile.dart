import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../domain/account.dart';
import '../../domain/account_type.dart';

/// Row for a single account, swipeable to soft-delete (with the standard
/// undo affordance handled by the screen that owns the Dismissible key).
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, required this.onTap});

  final Account account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(account.colorValue);

    return FlowFiCard(
      padding: EdgeInsets.zero,
      child: FlowFiListTile(
        onTap: onTap,
        leading:
            account.type == AccountType.bank || account.type == AccountType.card
            ? BankLogo(
                bankId: account.bankId,
                fallbackName: account.name,
                size: 44,
              )
            : FlowFiIconChip(icon: account.type.icon, color: color, size: 44),
        title: Text(account.name, style: context.textTheme.titleMedium),
        subtitle: Text(
          account.type.label,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: Text(
          CurrencyFormatter.instance.format(account.currentBalance),
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
