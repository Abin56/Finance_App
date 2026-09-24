import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// A 3-segment progress row (Upload → Review → Done) shown under the AppBar
/// on both [PdfImportScreen] and [PdfTransactionReviewScreen] so the
/// multi-screen flow reads as one guided process rather than disconnected
/// screens. Purely presentational — driven by whatever step the caller
/// already knows it's on via [PdfImportStage], no new state of its own.
class PdfImportStageDots extends StatelessWidget {
  const PdfImportStageDots({super.key, required this.currentStep});

  /// 0 = Upload, 1 = Review, 2 = Done.
  final int currentStep;

  static const _labels = ['Upload', 'Review', 'Done'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.sm,
        AppSizes.lg,
        AppSizes.md,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSizes.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= currentStep
                          ? AppColors.primary
                          : context.colors.outlineVariant,
                      borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    _labels[i],
                    textAlign: i == 0
                        ? TextAlign.start
                        : (i == _labels.length - 1
                              ? TextAlign.end
                              : TextAlign.center),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: i <= currentStep
                          ? context.colors.onSurface
                          : context.colors.onSurfaceVariant,
                      fontWeight: i == currentStep
                          ? FontWeight.w600
                          : FontWeight.normal,
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
