import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Shared presentation for the Loan & EMI section — the Flutter twin of the
/// web app's `loan-emi-ui.tsx`, so Loans and EMIs read as one product on
/// both platforms. Purely visual: every figure passed in is already derived
/// by the existing providers; nothing here computes money.
///
/// Terminology (identical on web):
///   Loan — money taken from or given to a bank, lender or person.
///   EMI  — installments for a purchase, Credit Card EMI or store finance.
abstract final class LoanEmiCopy {
  static const loan = 'Loan';
  static const loans = 'Loans';
  static const emi = 'EMI';
  static const emis = 'EMIs';
  static const loanDescription =
      'Money you took and need to repay, or gave and need to get back.';
  static const emiDescription =
      'Installments for a purchase, Credit Card EMI or store finance.';
  static const outstanding = 'Outstanding';
  static const stillToReceive = 'Still to receive';

  static const IconData loanIcon = Icons.account_balance_outlined;
  static const IconData emiIcon = Icons.shopping_bag_outlined;
}

/// Readable secondary text — the theme maps `onSurfaceVariant` to the
/// primary text color, so the real secondary tier comes from [AppColors].
Color loanEmiSecondaryText(BuildContext context) => context.isDarkMode
    ? AppColors.darkTextSecondary
    : AppColors.lightTextSecondary;

/// Accent for thin marks (progress fills) on a neutral surface: lime only
/// has contrast on dark, so light mode uses the near-black text color —
/// the same rule `AppTheme`'s `onSurfaceAccent` follows.
Color loanEmiAccent(BuildContext context) =>
    context.isDarkMode ? context.colors.primary : context.colors.onSurface;

/// Whole days from today until [date] (negative once past).
int loanEmiDaysUntil(DateTime date) =>
    date.dateOnly.difference(DateTime.now().dateOnly).inDays;

/// "Due today" / "Due in 3 days" / "Overdue by 2 days" / "Due 5 Mar".
String loanEmiDueLabel(DateTime date) {
  final days = loanEmiDaysUntil(date);
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days > 1 && days <= 7) return 'Due in $days days';
  if (days < 0) return 'Overdue by ${-days} day${days == -1 ? '' : 's'}';
  return 'Due ${date.shortDate}';
}

String _money(double amount) => CurrencyFormatter.instance.format(amount);

/// A small status label — only for non-routine states (Missed payment,
/// Closed, Completed, Money I lent). "Active" is the default and gets none.
class LoanEmiBadge {
  const LoanEmiBadge(this.label, this.color);
  final String label;
  final Color color;
}

class LoanEmiBadgeChip extends StatelessWidget {
  const LoanEmiBadgeChip(this.badge, {super.key});
  final LoanEmiBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: context.isDarkMode ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        badge.label,
        style: context.textTheme.labelSmall?.copyWith(
          color: badge.color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Neutral when there's nothing notable; the one colored status otherwise.
Color loanEmiNeutralBadgeColor(BuildContext context) =>
    loanEmiSecondaryText(context);

/// Installment progress bar with "N of M paid · K left".
class LoanEmiProgress extends StatelessWidget {
  const LoanEmiProgress({super.key, required this.paid, required this.total});

  final int paid;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final secondary = loanEmiSecondaryText(context);
    return Semantics(
      label: '$paid of $total installments paid',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: context.colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(loanEmiAccent(context)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$paid of $total paid',
                style: context.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(total - paid).clamp(0, total)} left',
                style: context.textTheme.labelMedium?.copyWith(
                  color: secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Loan/EMI list card. Visual weight is deliberately uneven: name and
/// outstanding amount carry the card; the next installment, progress and
/// links are secondary. Neutral surface and icon — the accent is reserved
/// for the progress fill.
class LoanEmiCard extends StatelessWidget {
  const LoanEmiCard({
    super.key,
    required this.icon,
    required this.name,
    required this.source,
    required this.outstandingLabel,
    required this.outstanding,
    required this.onTap,
    this.badges = const [],
    this.nextAmount,
    this.nextDate,
    this.overdue = false,
    this.paid = 0,
    this.total = 0,
    this.links = const [],
    this.muted = false,
  });

  final IconData icon;
  final String name;
  final String source;
  final List<LoanEmiBadge> badges;
  final String outstandingLabel;
  final double outstanding;
  final double? nextAmount;
  final DateTime? nextDate;
  final bool overdue;
  final int paid;
  final int total;
  final List<(IconData, String)> links;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = loanEmiSecondaryText(context);
    final radius = BorderRadius.circular(AppSizes.radiusLg);
    return Opacity(
      opacity: muted ? 0.7 : 1,
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: context.colors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              14,
              AppSizes.md,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    LoanEmiIconBox(icon: icon),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    if (badges.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final badge in badges) ...[
                            LoanEmiBadgeChip(badge),
                            if (badge != badges.last) const SizedBox(height: 4),
                          ],
                        ],
                      )
                    else
                      Icon(Icons.chevron_right_rounded, color: secondary),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            outstandingLabel,
                            style: context.textTheme.labelMedium?.copyWith(
                              color: secondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _money(outstanding),
                              style: context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (nextDate != null && nextAmount != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            loanEmiDueLabel(nextDate!),
                            style: context.textTheme.labelMedium?.copyWith(
                              color: overdue ? AppColors.error : secondary,
                              fontWeight: overdue
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _money(nextAmount!),
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (total > 1) ...[
                  const SizedBox(height: AppSizes.md),
                  LoanEmiProgress(paid: paid, total: total),
                ],
                if (links.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.md),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (linkIcon, label) in links)
                        LoanEmiLinkChip(icon: linkIcon, label: label),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral rounded-square icon holder used by cards, choices and linked rows.
class LoanEmiIconBox extends StatelessWidget {
  const LoanEmiIconBox({super.key, required this.icon, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: context.colors.outline),
      ),
      child: Icon(icon, size: size * 0.5, color: context.colors.onSurface),
    );
  }
}

class LoanEmiLinkChip extends StatelessWidget {
  const LoanEmiLinkChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        border: Border.all(color: context.colors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: loanEmiSecondaryText(context)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail-screen hero: the outstanding balance first and largest, progress
/// right under it, then the next installment callout.
class LoanEmiDetailHero extends StatelessWidget {
  const LoanEmiDetailHero({
    super.key,
    required this.kindLabel,
    required this.label,
    required this.amount,
    required this.paid,
    required this.total,
    this.badges = const [],
    this.nextAmount,
    this.nextDate,
    this.nextSequence,
  });

  final String kindLabel;
  final String label;
  final double amount;
  final int paid;
  final int total;
  final List<LoanEmiBadge> badges;
  final double? nextAmount;
  final DateTime? nextDate;
  final int? nextSequence;

  @override
  Widget build(BuildContext context) {
    final secondary = loanEmiSecondaryText(context);
    final overdue = nextDate != null && loanEmiDaysUntil(nextDate!) < 0;
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(color: context.colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: context.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              for (final badge in badges) ...[
                const SizedBox(width: 4),
                LoanEmiBadgeChip(badge),
              ],
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(amount),
              style: context.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: AppSizes.md),
            LoanEmiProgress(paid: paid, total: total),
          ],
          if (nextDate != null && nextAmount != null) ...[
            const SizedBox(height: AppSizes.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: overdue
                    ? AppColors.error.withValues(alpha: 0.1)
                    : context.colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(
                    overdue
                        ? Icons.error_outline_rounded
                        : Icons.event_outlined,
                    size: 18,
                    color: overdue ? AppColors.error : secondary,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next installment · ${loanEmiDueLabel(nextDate!)}',
                          style: context.textTheme.labelMedium?.copyWith(
                            color: overdue ? AppColors.error : secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (nextSequence != null)
                          Text(
                            '#$nextSequence of $total',
                            style: context.textTheme.labelSmall?.copyWith(
                              color: secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    _money(nextAmount!),
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LoanEmiFact {
  const LoanEmiFact(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
}

/// Compact two-column label/value grid for detail screens.
class LoanEmiFactGrid extends StatelessWidget {
  const LoanEmiFactGrid({super.key, required this.facts});

  final List<LoanEmiFact> facts;

  @override
  Widget build(BuildContext context) {
    final secondary = loanEmiSecondaryText(context);
    final rows = <Widget>[];
    for (var i = 0; i < facts.length; i += 2) {
      final pair = facts.sublist(i, (i + 2).clamp(0, facts.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < 2; j++) ...[
                if (j == 1)
                  VerticalDivider(width: 1, color: context.colors.outline),
                Expanded(
                  child: j < pair.length
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.md,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pair[j].label,
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: secondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pair[j].value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.bodyMedium?.copyWith(
                                  fontWeight: pair[j].strong
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
      if (i + 2 < facts.length) {
        rows.add(Divider(height: 1, color: context.colors.outline));
      }
    }
    return LoanEmiGroup(children: rows);
  }
}

/// A bordered surface grouping rows with hairline dividers.
class LoanEmiGroup extends StatelessWidget {
  const LoanEmiGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: context.colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A linked record row (Account / Credit Card / Person) — tappable when it
/// can take the user to that record's own FlowFi section.
class LoanEmiLinkedRow extends StatelessWidget {
  const LoanEmiLinkedRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onOpen,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final secondary = loanEmiSecondaryText(context);
    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          child: Row(
            children: [
              LoanEmiIconBox(icon: icon, size: 34),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpen != null)
                Icon(Icons.north_east_rounded, size: 18, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading for detail screens.
class LoanEmiSectionTitle extends StatelessWidget {
  const LoanEmiSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Progressive disclosure for optional form fields — collapsed for a new
/// record so a first-time user only sees what's needed; the subtitle says
/// what's inside before they open it.
class LoanEmiMoreOptions extends StatelessWidget {
  const LoanEmiMoreOptions({
    super.key,
    required this.summary,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String summary;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSizes.radiusMd);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: context.colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSizes.md,
          0,
          AppSizes.md,
          AppSizes.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(
          'More options',
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          summary,
          style: context.textTheme.bodySmall?.copyWith(
            color: loanEmiSecondaryText(context),
          ),
        ),
        children: children,
      ),
    );
  }
}

/// Switch row that reveals its [children] only when on — e.g. "It's on a
/// credit card", so card controls never appear until they're relevant.
class LoanEmiRevealSwitch extends StatelessWidget {
  const LoanEmiRevealSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.children = const [],
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // A Material (not a decorated box) so the SwitchListTile's ink shows.
    return Material(
      color: value
          ? context.colors.surfaceContainerHighest.withValues(alpha: 0.6)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        side: BorderSide(color: context.colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: value,
            onChanged: onChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            title: Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: subtitle == null
                ? null
                : Text(
                    subtitle!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: loanEmiSecondaryText(context),
                    ),
                  ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: value && children.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.md,
                      0,
                      AppSizes.md,
                      AppSizes.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Small field heading above chip/segmented choices.
class LoanEmiFieldLabel extends StatelessWidget {
  const LoanEmiFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: context.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
