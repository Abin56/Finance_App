import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';
import '../../domain/person.dart';
import 'person_avatar.dart';

/// Row for a single person — avatar, name with an inline "Needs to Pay Me"/
/// "I Need to Pay"/"Nothing to Pay" pill, a plain-language "you lent ₹X"/
/// "you need to pay ₹X"/"nothing to pay" subtitle, and the balance amount
/// on the trailing edge. Swipeable to soft-delete, handled by the screen
/// that owns the Dismissible key.
class PersonTile extends StatelessWidget {
  const PersonTile({super.key, required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final direction = MoneyDirectionX.forSignedBalance(person.currentBalance) ?? MoneyDirection.completed;
    final amount = CurrencyFormatter.instance.format(person.currentBalance.abs());
    final subtitle = person.currentBalance == 0
        ? 'nothing to pay'
        : person.isCreditor
        ? 'you lent $amount'
        : 'you need to pay $amount';
    final pillLabel = person.currentBalance == 0
        ? 'Nothing to Pay'
        : person.isCreditor
        ? 'Needs to Pay Me'
        : 'I Need to Pay';

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Row(
            children: [
              PersonAvatar(name: person.name, colorValue: person.avatarColorValue),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            style: context.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSizes.xs),
                        _Pill(label: pillLabel, color: direction.color),
                      ],
                    ),
                    Text(
                      subtitle,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                CurrencyFormatter.instance.format(person.currentBalance.abs()),
                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: direction.color),
              ),
              const SizedBox(width: AppSizes.xs),
              Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
