import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';
import '../../domain/person.dart';
import '../../domain/person_timeline_entry.dart';
import 'person_avatar.dart';

/// Opening balance, totals per movement type, and current outstanding —
/// the summary stats every person statement page requires, folded once
/// from the (already-loaded) timeline by the screen and passed in.
class PersonStatementHeader extends StatelessWidget {
  const PersonStatementHeader({super.key, required this.person, required this.entries});

  final Person person;
  final List<PersonTimelineEntry> entries;

  /// Money that moved from the user to this person — a plain-language
  /// "given" total covering lending money out ("Money given"/"Money lent")
  /// and paying back what the user had borrowed ("Money repaid").
  static const _givenTitles = {'Money given', 'Money repaid', 'Money lent'};

  /// Money that moved from this person to the user.
  static const _receivedTitles = {'Money borrowed', 'Money received back', 'Loan payment received'};

  double _totalFor(Set<String> titles) =>
      entries.where((e) => titles.contains(e.title)).fold(0.0, (total, e) => total + e.signedAmount.abs());

  double _totalForCategory(PersonTimelineCategory category) =>
      entries.where((e) => e.category == category).fold(0.0, (total, e) => total + e.signedAmount.abs());

  double get _totalSettled => entries.where((e) => e.isSettlement).fold(0.0, (total, e) => total + e.signedAmount.abs());

  /// Money the user handed to this person and hasn't gotten back — the
  /// "gave"/"Money lent" side of lending, excluding split/assigned expenses
  /// (those are tracked separately in [PersonPendingBreakdown]).
  double get _youLent => entries
      .where((e) => e.category == PersonTimelineCategory.lending && e.signedAmount > 0)
      .fold(0.0, (total, e) => total + e.signedAmount);

  /// Money this person handed to the user and hasn't paid back.
  double get _youBorrowed => entries
      .where((e) => e.category == PersonTimelineCategory.lending && e.signedAmount < 0)
      .fold(0.0, (total, e) => total + e.signedAmount.abs());

  @override
  Widget build(BuildContext context) {
    final direction = MoneyDirectionX.forSignedBalance(person.currentBalance) ?? MoneyDirection.completed;

    final lastTransactionDate = entries.isEmpty
        ? null
        : entries.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: person.name, colorValue: person.avatarColorValue, radius: 28),
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
                            style: context.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSizes.xs),
                        MoneyDirectionBadge(direction: direction, compact: true),
                      ],
                    ),
                    Text(
                      'Joined ${person.createdAt.monthYear}',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          Text(
            'Amount Left',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            CurrencyFormatter.instance.format(person.currentBalance.abs()),
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: direction.color),
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Expanded(child: _StatColumn(label: 'Total Paid Back', value: _totalSettled, color: AppColors.success)),
              Expanded(child: _StatColumn(label: 'You Lent', value: _youLent, color: AppColors.success)),
              Expanded(child: _StatColumn(label: 'You Borrowed', value: _youBorrowed, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _StatRow(label: 'Starting Amount Left', value: person.openingBalance),
          _StatRow(label: 'Total money given', value: _totalFor(_givenTitles)),
          _StatRow(label: 'Total money received', value: _totalFor(_receivedTitles)),
          _StatRow(label: 'Total lending', value: _totalForCategory(PersonTimelineCategory.lending)),
          _StatRow(label: 'Total expenses this person will pay', value: _totalForCategory(PersonTimelineCategory.assignedExpense)),
          _StatRow(label: 'Total shared expenses', value: _totalForCategory(PersonTimelineCategory.splitExpense)),
          const SizedBox(height: AppSizes.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Last transaction',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                lastTransactionDate == null ? 'None yet' : lastTransactionDate.shortDate,
                style: context.textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 2),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(CurrencyFormatter.instance.format(value), style: context.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
