import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';
import '../../domain/person.dart';
import 'person_avatar.dart';

/// Row for a single person — avatar, name with an inline "Needs to Pay Me"/
/// "I Need to Pay"/"Nothing to Pay" pill, a plain-language "you lent ₹X"/
/// "you need to pay ₹X"/"nothing to pay" subtitle, and the balance amount
/// on the trailing edge. Swipeable to soft-delete, handled by the screen
/// that owns the Dismissible key. Built on [FlowFiListTile] — the same row
/// primitive [LoanTile] uses, so both read as one consistent shape.
class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.person,
    required this.onTap,
    this.balance,
  });

  final Person person;
  final VoidCallback onTap;

  /// Net position (direct ledger + Loans — [personPositionProvider]).
  /// Defaults to the ledger balance for callers that don't pass one.
  final double? balance;

  @override
  Widget build(BuildContext context) {
    final balance = this.balance ?? person.currentBalance;
    final direction =
        MoneyDirectionX.forSignedBalance(balance) ?? MoneyDirection.completed;
    final amount = CurrencyFormatter.instance.format(balance.abs());
    final subtitle = balance == 0
        ? 'nothing to pay'
        : balance > 0
        ? 'they owe you $amount'
        : 'you need to pay $amount';
    final pillLabel = balance == 0
        ? 'Nothing to Pay'
        : balance > 0
        ? 'Needs to Pay Me'
        : 'I Need to Pay';

    return FlowFiListTile(
      onTap: onTap,
      leading: PersonAvatar(
        name: person.name,
        colorValue: person.avatarColorValue,
        radius: 18,
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              person.name,
              style: context.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSizes.xs),
          _Pill(label: pillLabel, color: direction.color),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: FlowFiAmountText(amount, color: direction.color),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}
