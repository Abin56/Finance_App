import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../domain/loan.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_status.dart';
import '../../domain/loan_title.dart';
import '../providers/loan_providers.dart';
import 'loan_direction_badge.dart';

/// Row for a single loan — borrower avatar, loan name (or a "Loan to
/// {person}" fallback), amount remaining, and status badge. Swipeable to
/// soft-delete, handled by the screen that owns the Dismissible key. Built
/// on [FlowFiListTile] — the same row primitive [PersonTile] uses, so both
/// read as one consistent shape.
class LoanTile extends ConsumerWidget {
  const LoanTile({
    super.key,
    required this.loan,
    required this.person,
    required this.onTap,
  });

  final Loan loan;
  final Person? person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loanStatusProvider(loan));
    final remaining = ref.watch(loanRemainingAmountProvider(loan));
    final title = loanDisplayTitle(loan, person);

    return FlowFiListTile(
      onTap: onTap,
      leading: person != null
          ? PersonAvatar(
              name: person!.name,
              colorValue: person!.avatarColorValue,
              radius: 18,
            )
          : FlowFiIconChip(
              icon: Icons.account_balance_outlined,
              color: status.color,
              size: 36,
            ),
      title: Text(
        title,
        style: context.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              style: context.textTheme.bodySmall?.copyWith(color: status.color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          LoanDirectionBadge(direction: loan.direction),
        ],
      ),
      trailing: FlowFiAmountText(CurrencyFormatter.instance.format(remaining)),
      trailingSubtitle: Text(
        loan.direction == LoanDirection.given
            ? 'left to receive'
            : 'left to pay',
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
