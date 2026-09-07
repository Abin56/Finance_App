import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../smart_import/presentation/widgets/detected_transaction_tile.dart';
import '../providers/paste_import_providers.dart';
import '../providers/paste_import_state.dart';
import '../widgets/paste_detected_transaction_edit_sheet.dart';

/// The staged review for Copy/Paste Import — nothing here has touched
/// Firestore yet. A copy of Smart Import's `TransactionReviewScreen` wired to
/// [pasteImportControllerProvider] instead (that screen hardcodes the
/// Screenshot session's provider, so it can't be reused directly), but reuses
/// `DetectedTransactionTile` as-is since that widget only depends on plain
/// callbacks, not on which controller owns the session.
class PasteTransactionReviewScreen extends ConsumerWidget {
  const PasteTransactionReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pasteImportControllerProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    final state = ref.watch(pasteImportControllerProvider);

    return PopScope(
      canPop: state.stage != PasteImportStage.importing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titleFor(state)),
          automaticallyImplyLeading: state.stage != PasteImportStage.importing,
        ),
        body: switch (state.stage) {
          PasteImportStage.importing => _ImportingView(state: state),
          PasteImportStage.done => _ImportSummaryScreenBody(state: state),
          _ => _ReviewBody(state: state),
        },
      ),
    );
  }

  String _titleFor(PasteImportState state) => switch (state.stage) {
        PasteImportStage.done => 'Import complete',
        PasteImportStage.importing => 'Importing…',
        _ => 'Paste Transactions',
      };
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.state});
  final PasteImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pasteImportControllerProvider.notifier);
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];

    if (state.detected.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions found',
        subtitle: 'Make sure the pasted text contains transaction details.',
      );
    }

    // Mirrors `PasteImportState.readyCount` exactly — what will actually be
    // attempted if the user imports right now.
    final readyForImport = state.detected
        .where(
          (d) =>
              d.isSelected &&
              d.hasRequiredFields &&
              (!d.isDuplicate || d.duplicateAcknowledged),
        )
        .toList();
    final missingCategoryCount = readyForImport.where((d) => d.categoryId == null).length;
    // Selected despite still needing review (e.g. the user manually
    // re-checked a row without fixing it) — these will never be attempted,
    // so the button's count intentionally excludes them; call that out
    // explicitly rather than leaving the user to wonder why the number is
    // lower than what they checked.
    final selectedNeedsReviewCount = state.detected
        .where((d) => d.isSelected && !d.hasRequiredFields && (!d.isDuplicate || d.duplicateAcknowledged))
        .length;
    final allSelected = state.detected.isNotEmpty && state.detected.every((d) => d.isSelected);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${state.detected.length} transaction${state.detected.length == 1 ? '' : 's'} detected',
                      style: context.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: allSelected ? controller.deselectAll : controller.selectAll,
                    child: Text(allSelected ? 'Deselect all' : 'Select all'),
                  ),
                ],
              ),
              if (state.needsReviewCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSizes.xs),
                  child: Text(
                    '${state.needsReviewCount} transaction${state.needsReviewCount == 1 ? '' : 's'} need review',
                    style: context.textTheme.bodySmall?.copyWith(color: AppColors.pending),
                  ),
                ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String>(
                initialValue: state.accountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Account',
                  isDense: true,
                ),
                hint: const Text('Select which account these belong to'),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BankLogo(bankId: account.bankId, fallbackName: account.name, size: 20),
                          const SizedBox(width: AppSizes.sm),
                          Flexible(child: Text(account.name, overflow: TextOverflow.ellipsis)),
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
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.lg),
            itemCount: state.detected.length,
            itemBuilder: (context, index) {
              final transaction = state.detected[index];
              final categoryName = categories
                  .firstWhereOrNull((c) => c.id == transaction.categoryId)
                  ?.name;
              return DetectedTransactionTile(
                transaction: transaction,
                categoryName: categoryName,
                onToggleSelected: (selected) => controller.toggleSelected(transaction.id, selected),
                onTap: () => PasteDetectedTransactionEditSheet.show(context, transaction),
                onSkipDuplicate: () => controller.skipDuplicate(transaction.id),
                onImportAnywayDuplicate: () => controller.importDuplicateAnyway(transaction.id),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.accountId == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSizes.sm),
                    child: Text(
                      'Select an account to continue',
                      style: TextStyle(color: AppColors.pending),
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  if (missingCategoryCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: Text(
                        '$missingCategoryCount selected transaction${missingCategoryCount == 1 ? '' : 's'} '
                        'need a category before they can be imported.',
                        style: const TextStyle(color: AppColors.pending),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (selectedNeedsReviewCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: Text(
                        '$selectedNeedsReviewCount selected transaction${selectedNeedsReviewCount == 1 ? '' : 's'} '
                        "still need${selectedNeedsReviewCount == 1 ? 's' : ''} review and won't be imported yet.",
                        style: const TextStyle(color: AppColors.pending),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
                PrimaryButton(
                  label: 'Import Selected (${readyForImport.length})',
                  onPressed: state.accountId != null &&
                          readyForImport.isNotEmpty &&
                          missingCategoryCount == 0
                      ? controller.import
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.state});
  final PasteImportState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.importProgress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSizes.lg),
          Text('Importing…', style: context.textTheme.titleMedium),
          if (progress != null) ...[
            const SizedBox(height: AppSizes.xs),
            Text('${progress.$1} / ${progress.$2}', style: context.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _ImportSummaryScreenBody extends ConsumerWidget {
  const _ImportSummaryScreenBody({required this.state});
  final PasteImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = state.importResult;
    if (result == null) return const SizedBox.shrink();

    final lines = <String>['${result.imported} imported'];
    if (result.skippedDuplicates > 0) lines.add('${result.skippedDuplicates} skipped as duplicates');
    if (result.failed > 0) lines.add('${result.failed} failed');

    return EmptyState(
      icon: result.hasIssues ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
      title: result.hasIssues ? 'Import completed with some issues' : 'Import complete',
      subtitle: lines.join('\n'),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.failed > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: OutlinedButton(
                onPressed: () => ref.read(pasteImportControllerProvider.notifier).retryImport(),
                child: const Text('Retry failed'),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
