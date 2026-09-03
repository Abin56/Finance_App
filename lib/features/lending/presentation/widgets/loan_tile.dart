import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
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
/// soft-delete, handled by the screen that owns the Dismissible key.
class LoanTile extends ConsumerWidget {
  const LoanTile({super.key, required this.loan, required this.person, required this.onTap});

  final Loan loan;
  final Person? person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loanStatusProvider(loan));
    final remaining = ref.watch(loanRemainingAmountProvider(loan));
    final title = loanDisplayTitle(loan, person);

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
              if (person != null) PersonAvatar(name: person!.name, colorValue: person!.avatarColorValue),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.textTheme.titleMedium),
                    Row(
                      children: [
                        Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                        const SizedBox(width: AppSizes.xs),
                        Flexible(
                          child: Text(
                            status.label,
                            style: context.textTheme.bodySmall?.copyWith(color: status.color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSizes.xs),
                        LoanDirectionBadge(direction: loan.direction),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(remaining),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    loan.direction == LoanDirection.given ? 'left to receive' : 'left to pay',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
