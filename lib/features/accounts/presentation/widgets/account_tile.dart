import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_logo.dart';
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

    return ClayCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Row(
        children: [
          if (account.type == AccountType.bank || account.type == AccountType.card)
            BankLogo(bankId: account.bankId, fallbackName: account.name, size: 44)
          else
            ClayIconChip(icon: account.type.icon, color: color, size: 44, iconSize: 22),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: context.textTheme.titleMedium),
                Text(
                  account.type.label,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.instance.format(account.currentBalance),
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
