import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../providers/pdf_import_providers.dart';
import '../providers/pdf_import_state.dart';
import '../widgets/pdf_detected_transaction_edit_sheet.dart';
import '../widgets/pdf_detected_transaction_tile.dart';
import '../widgets/pdf_import_stage_dots.dart';

/// The staged review for PDF Statement import — nothing here has touched
/// Firestore yet. A copy of Paste Import's `PasteTransactionReviewScreen`
/// (itself a copy of Smart Import's `TransactionReviewScreen`) wired to
/// [pdfImportControllerProvider] instead, since each session's review screen
/// hardcodes its own controller and can't be shared as-is. Reuses
/// `DetectedTransactionTile` unchanged since that widget only depends on
/// plain callbacks, not on which controller owns the session — wrapped here
/// in a `Dismissible` to add swipe-to-remove, since that's a capability this
/// review needs that the shared tile doesn't expose on its own.
class PdfTransactionReviewScreen extends ConsumerWidget {
  const PdfTransactionReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pdfImportControllerProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    final state = ref.watch(pdfImportControllerProvider);

    return PopScope(
      canPop: state.stage != PdfImportStage.importing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titleFor(state)),
          automaticallyImplyLeading: state.stage != PdfImportStage.importing,
        ),
        body: Column(
          children: [
            PdfImportStageDots(currentStep: _stepFor(state)),
            Expanded(
              child: switch (state.stage) {
                PdfImportStage.importing => _ImportingView(state: state),
                PdfImportStage.done => _ImportSummaryScreenBody(state: state),
                _ => _ReviewBody(state: state),
              },
            ),
          ],
        ),
      ),
    );
  }

  String _titleFor(PdfImportState state) => switch (state.stage) {
    PdfImportStage.done => 'Import complete',
    PdfImportStage.importing => 'Importing…',
    _ => 'PDF Statement',
  };

  int _stepFor(PdfImportState state) => switch (state.stage) {
    PdfImportStage.done => 2,
    PdfImportStage.importing => 1,
    _ => 1,
  };
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.state});
  final PdfImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pdfImportControllerProvider.notifier);
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];

    if (state.detected.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions found',
        subtitle: 'We could not find transaction rows in this statement.',
      );
    }

    // Mirrors `PdfImportState.readyCount` exactly — what will actually be
    // attempted if the user imports right now.
    final readyForImport = state.detected
        .where(
          (d) =>
              d.isSelected &&
              d.hasRequiredFields &&
              (!d.isDuplicate || d.duplicateAcknowledged),
        )
        .toList();
    final missingCategoryCount = readyForImport
        .where((d) => d.categoryId == null)
        .length;
    // Selected despite still needing review (e.g. the user manually
    // re-checked a row without fixing it) — these will never be attempted,
    // so the button's count intentionally excludes them; call that out
    // explicitly rather than leaving the user to wonder why the number is
    // lower than what they checked.
    final selectedNeedsReviewCount = state.detected
        .where(
          (d) =>
              d.isSelected &&
              !d.hasRequiredFields &&
              (!d.isDuplicate || d.duplicateAcknowledged),
        )
        .length;
    final allSelected =
        state.detected.isNotEmpty && state.detected.every((d) => d.isSelected);
    final readyCount = state.detected.length - state.needsReviewCount;
    final totalAmount = state.detected.fold<double>(
      0,
      (sum, d) => sum + (d.amount ?? 0),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.md,
            AppSizes.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      // Deliberately "N Transactions" rather than any
                      // bank-name claim — the parser is validated only
                      // against synthetic layouts, never a specific bank.
                      '${state.detected.length} Transaction${state.detected.length == 1 ? '' : 's'}',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.instance.format(totalAmount),
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Total Amount',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.flowfi.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  _CountBadge(
                    label: '$readyCount Ready',
                    color: AppColors.income,
                  ),
                  if (state.needsReviewCount > 0) ...[
                    const SizedBox(width: AppSizes.sm),
                    _CountBadge(
                      label: '${state.needsReviewCount} Need Review',
                      color: AppColors.pending,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSizes.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.xs,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: context.colors.outlineVariant),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSizes.xs),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: AppSizes.iconSm,
                            color: context.colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSizes.xs),
                          Text(
                            'Account',
                            style: context.textTheme.labelMedium?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: state.accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: AppSizes.xs,
                        ),
                      ),
                      hint: const Text('Select which account these belong to'),
                      items: [
                        for (final account in accounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BankLogo(
                                  bankId: account.bankId,
                                  fallbackName: account.name,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSizes.sm),
                                Flexible(
                                  child: Text(
                                    account.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) controller.setAccount(value);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.md,
            AppSizes.lg,
            0,
          ),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: (_) => allSelected
                    ? controller.deselectAll()
                    : controller.selectAll(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: AppSizes.xs),
              Text('Select all', style: context.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${state.detected.where((d) => d.isSelected).length} selected',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.flowfi.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              AppSizes.md,
              AppSizes.lg,
              AppSizes.lg,
            ),
            itemCount: state.detected.length,
            itemBuilder: (context, index) {
              final transaction = state.detected[index];
              final category = categories.firstWhereOrNull(
                (c) => c.id == transaction.categoryId,
              );
              return Dismissible(
                key: ValueKey(transaction.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: AppSizes.sm),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.lg,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.expense,
                  ),
                ),
                onDismissed: (_) =>
                    controller.removeTransaction(transaction.id),
                child: PdfDetectedTransactionTile(
                  transaction: transaction,
                  category: category,
                  onToggleSelected: (selected) =>
                      controller.toggleSelected(transaction.id, selected),
                  onTap: () => PdfDetectedTransactionEditSheet.show(
                    context,
                    transaction,
                  ),
                  onSkipDuplicate: () =>
                      controller.skipDuplicate(transaction.id),
                  onImportAnywayDuplicate: () =>
                      controller.importDuplicateAnyway(transaction.id),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              0,
              AppSizes.lg,
              AppSizes.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReviewFooterNotice(
                  messages: [
                    if (state.accountId == null)
                      'Select an account to continue'
                    else ...[
                      if (missingCategoryCount > 0)
                        '$missingCategoryCount selected transaction${missingCategoryCount == 1 ? '' : 's'} '
                            'need a category before they can be imported.',
                      if (selectedNeedsReviewCount > 0)
                        '$selectedNeedsReviewCount selected transaction${selectedNeedsReviewCount == 1 ? '' : 's'} '
                            "still need${selectedNeedsReviewCount == 1 ? 's' : ''} review and won't be imported yet.",
                    ],
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${readyForImport.length} transaction${readyForImport.length == 1 ? '' : 's'} selected',
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.flowfi.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Flexible(
                      child: _ImportPillButton(
                        label: 'Import ${readyForImport.length} Transactions',
                        onPressed:
                            state.accountId != null &&
                                readyForImport.isNotEmpty &&
                                missingCategoryCount == 0
                            ? controller.import
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The rounded, trailing-chevron "Import N Transactions" pill button — a
/// one-off style distinct from the app's standard [PrimaryButton] (which
/// puts its optional icon before the label, not after), so this is a small
/// local widget rather than a change to that shared component.
class _ImportPillButton extends StatelessWidget {
  const _ImportPillButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.sm + 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSizes.xs),
          const Icon(Icons.arrow_forward_rounded, size: AppSizes.iconSm),
        ],
      ),
    );
  }
}

/// A pill badge used next to the "N transactions found" title to call out
/// a secondary count (e.g. "N need review") without stacking a whole extra
/// line of colored text underneath, as the previous layout did.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Consolidates every currently-true footer warning (no account selected,
/// missing category, still needs review) into one amber notice card instead
/// of several separately-margined colored text lines — same visual idiom as
/// [DetectedTransactionTile]'s duplicate-warning box. Renders nothing when
/// [messages] is empty.
class _ReviewFooterNotice extends StatelessWidget {
  const _ReviewFooterNotice({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: AppSizes.iconSm,
            color: AppColors.pending,
          ),
          const SizedBox(width: AppSizes.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < messages.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      top: i == 0 ? 0 : AppSizes.xs,
                    ),
                    child: Text(
                      messages[i],
                      style: context.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.state});
  final PdfImportState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.importProgress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSizes.lg),
            Text('Importing…', style: context.textTheme.titleMedium),
            if (progress != null) ...[
              const SizedBox(height: AppSizes.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                child: LinearProgressIndicator(
                  value: progress.$2 == 0 ? null : progress.$1 / progress.$2,
                  minHeight: 6,
                  color: AppColors.primary,
                  backgroundColor: context.colors.outlineVariant,
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                '${progress.$1} / ${progress.$2}',
                style: context.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportSummaryScreenBody extends ConsumerWidget {
  const _ImportSummaryScreenBody({required this.state});
  final PdfImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = state.importResult;
    if (result == null) return const SizedBox.shrink();

    final lines = <String>['${result.imported} imported'];
    if (result.skippedDuplicates > 0) {
      lines.add('${result.skippedDuplicates} skipped as duplicates');
    }
    if (result.failed > 0) lines.add('${result.failed} failed');

    return EmptyState(
      icon: result.hasIssues
          ? Icons.warning_amber_rounded
          : Icons.check_circle_outline_rounded,
      title: result.hasIssues
          ? 'Import completed with some issues'
          : 'Import complete',
      subtitle: lines.join('\n'),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.failed > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: OutlinedButton(
                onPressed: () => ref
                    .read(pdfImportControllerProvider.notifier)
                    .retryImport(),
                child: const Text('Retry failed'),
              ),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
