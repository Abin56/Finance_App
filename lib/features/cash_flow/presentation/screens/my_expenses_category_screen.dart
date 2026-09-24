import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/flowfi_amount_text.dart';
import '../../domain/money_flow_line.dart';
import '../providers/cash_flow_providers.dart';

/// "My Expenses" drill-down, level 2 — every [MyExpenseLine] within one
/// category for the selected range. Reads [myExpensesForCategoryProvider]
/// directly so this screen's footer total is guaranteed to equal the
/// category total shown on [MyExpensesHistoryScreen] — both fold the same
/// filtered slice of [myExpenseLinesForRangeProvider].
class MyExpensesCategoryScreen extends ConsumerWidget {
  const MyExpensesCategoryScreen({
    super.key,
    required this.categoryId,
    required this.categoryLabel,
  });

  final String categoryId;
  final String categoryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(myExpensesForCategoryProvider(categoryId));
    final total = lines.fold(0.0, (sum, l) => sum + l.myShare);

    return Scaffold(
      appBar: AppBar(title: Text(categoryLabel)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.lg,
                AppSizes.lg,
                AppSizes.lg,
                AppSizes.md,
              ),
              child: FlowFiCard(
                padding: const EdgeInsets.all(AppSizes.md),
                child: FlowFiAmountText(
                  CurrencyFormatter.instance.format(total),
                  size: AmountSize.large,
                ),
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No expenses found for this period',
                      subtitle:
                          'Nothing in this category for the selected range.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.lg,
                        0,
                        AppSizes.lg,
                        AppSizes.fabClearance,
                      ),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final showDateHeader =
                            index == 0 ||
                            !lines[index - 1].date.isSameDay(line.date);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showDateHeader)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: index == 0 ? 0 : AppSizes.md,
                                  bottom: AppSizes.xs,
                                ),
                                child: Text(
                                  line.date.sectionLabel,
                                  style: context.textTheme.labelLarge?.copyWith(
                                    color: context.colors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            _MyExpenseLineTile(line: line),
                          ],
                        );
                      },
                    ),
            ),
            if (lines.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.lg,
                  vertical: AppSizes.md,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border(
                    top: BorderSide(color: context.colors.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.instance.format(total),
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MyExpenseLineTile extends StatelessWidget {
  const _MyExpenseLineTile({required this.line});

  final MyExpenseLine line;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (line.accountLabel != null) line.accountLabel!,
      if (line.notes.isNotEmpty) line.notes,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line.title,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (line.isSplit) ...[
                      const SizedBox(width: AppSizes.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        // A "Shared" tag is outside the money-direction palette and
                        // isn't a CTA/selection state, so it uses the purple tag
                        // accent rather than lime (lime text on a light tint fails
                        // the color-usage rule — see AppColors' docs).
                        child: Text(
                          'Shared',
                          style: context.textTheme.labelSmall?.copyWith(
                            color: AppColors.purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join(' · '),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (line.isSplit && line.totalAmount != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Total bill: ${CurrencyFormatter.instance.format(line.totalAmount!)}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.instance.format(line.myShare),
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (line.isSplit)
                Text(
                  'My share',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
