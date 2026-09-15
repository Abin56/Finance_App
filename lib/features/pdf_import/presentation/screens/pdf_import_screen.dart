import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../providers/pdf_import_providers.dart';
import '../providers/pdf_import_state.dart';
import '../widgets/pdf_import_stage_dots.dart';
import '../widgets/pdf_password_dialog.dart';
import 'pdf_transaction_review_screen.dart';

/// PDF Statement Import's entry screen — the user picks a statement PDF
/// (optionally entering its password), FlowFi extracts and parses it, then
/// hands off to the review screen. Reached from `showAddEntryMenu`'s "PDF
/// Statement" option, and optionally from a specific account's own screen
/// (in which case that account is preselected once the review screen
/// opens). A sibling of `SmartImportScreen`/`PasteImportScreen` — same
/// session-reset-on-open and stage-driven navigation pattern, applied to a
/// file picker instead of an image picker or text field.
class PdfImportScreen extends ConsumerStatefulWidget {
  const PdfImportScreen({super.key, this.initialAccountId});

  final String? initialAccountId;

  static Future<void> show(BuildContext context, {String? initialAccountId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfImportScreen(initialAccountId: initialAccountId),
      ),
    );
  }

  @override
  ConsumerState<PdfImportScreen> createState() => _PdfImportScreenState();
}

class _PdfImportScreenState extends ConsumerState<PdfImportScreen> {
  bool _passwordDialogShown = false;

  @override
  void initState() {
    super.initState();
    // Reset any leftover state from a previous session before this screen
    // starts contributing to it, then apply the account preselection.
    Future.microtask(() {
      final controller = ref.read(pdfImportControllerProvider.notifier);
      controller.reset();
      controller.preselectAccount(widget.initialAccountId);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PdfImportState>(pdfImportControllerProvider, (previous, next) {
      final enteredReview =
          previous?.stage != PdfImportStage.reviewing &&
          next.stage == PdfImportStage.reviewing;
      if (enteredReview) {
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => const PdfTransactionReviewScreen(),
          ),
        );
      }

      final needsPassword = next.stage == PdfImportStage.awaitingPassword;
      if (needsPassword && !_passwordDialogShown) {
        _passwordDialogShown = true;
        PdfPasswordDialog.show(context).then((_) {
          _passwordDialogShown = false;
          // The dialog was dismissed (cancelled) rather than closed by the
          // controller reaching a non-awaitingPassword stage — reset so the
          // user lands back on file selection instead of a stuck screen.
          if (ref.read(pdfImportControllerProvider).stage ==
              PdfImportStage.awaitingPassword) {
            ref.read(pdfImportControllerProvider.notifier).reset();
          }
        });
      }

      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    final state = ref.watch(pdfImportControllerProvider);
    final isBusy =
        state.stage == PdfImportStage.opening ||
        state.stage == PdfImportStage.extracting ||
        state.stage == PdfImportStage.parsing;

    return Scaffold(
      appBar: AppBar(title: const Text('PDF Statement')),
      body: Column(
        children: [
          const PdfImportStageDots(currentStep: 0),
          Expanded(
            child: isBusy ? _BusyView(state: state) : const _PickFileView(),
          ),
        ],
      ),
    );
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView({required this.state});
  final PdfImportState state;

  @override
  Widget build(BuildContext context) {
    // `processingLabel` carries OCR's per-page progress ("Scanning page 2
    // of 8…") when set; otherwise fall back to a stage-appropriate default
    // for the (usually instant) embedded-text path.
    final label =
        state.processingLabel ??
        switch (state.stage) {
          PdfImportStage.opening || PdfImportStage.extracting =>
            'Reading PDF…',
          PdfImportStage.parsing => 'Finding transactions…',
          _ => 'Working…',
        };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSizes.lg),
          Text(
            label,
            style: context.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PickFileView extends ConsumerWidget {
  const _PickFileView();

  static const _steps = [
    ('Choose a PDF', Icons.description_outlined),
    ('We find the transactions', Icons.search_rounded),
    ('Review before anything saves', Icons.fact_check_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pdfImportControllerProvider.notifier);
    final heroBg = context.isDarkMode
        ? AppColors.raisedDark
        : AppColors.nearBlack;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSizes.xl),
              decoration: BoxDecoration(
                color: heroBg,
                borderRadius: BorderRadius.circular(AppSizes.radiusCard),
                boxShadow: AppShadows.soft(context),
              ),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.limeStrong.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: AppSizes.iconXl,
                      color: AppColors.limeStrong,
                    ),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Text(
                    'Upload your statement',
                    style: context.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    'A PDF from your bank or credit card — nothing is saved '
                    'until you confirm.',
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xl),
            for (var i = 0; i < _steps.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _steps.length - 1 ? 0 : AppSizes.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _steps[i].$2,
                        size: AppSizes.iconSm,
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Text(
                        _steps[i].$1,
                        style: context.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(
              label: 'Choose PDF',
              icon: Icons.upload_file_rounded,
              onPressed: controller.pickFile,
            ),
          ],
        ),
      ),
    );
  }
}
