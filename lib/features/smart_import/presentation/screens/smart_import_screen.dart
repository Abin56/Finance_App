import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../providers/smart_import_providers.dart';
import '../providers/smart_import_state.dart';
import 'camera_capture_screen.dart';
import 'transaction_review_screen.dart';

/// Smart Import's entry screen — select one or more screenshots and/or scan
/// with the camera (see [CameraCaptureScreen]), then hand off to
/// OCR/extraction. Reached from `showAddEntryMenu`'s "Smart Import" option,
/// and optionally from a specific account's own screen (in which case that
/// account is preselected once the review screen opens).
class SmartImportScreen extends ConsumerStatefulWidget {
  const SmartImportScreen({super.key, this.initialAccountId});

  final String? initialAccountId;

  static Future<void> show(BuildContext context, {String? initialAccountId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SmartImportScreen(initialAccountId: initialAccountId),
      ),
    );
  }

  @override
  ConsumerState<SmartImportScreen> createState() => _SmartImportScreenState();
}

class _SmartImportScreenState extends ConsumerState<SmartImportScreen> {
  @override
  void initState() {
    super.initState();
    // Reset any leftover state from a previous session before this screen
    // starts contributing to it, then apply the account preselection.
    Future.microtask(() {
      final controller = ref.read(smartImportControllerProvider.notifier);
      controller.reset();
      controller.preselectAccount(widget.initialAccountId);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SmartImportState>(smartImportControllerProvider, (
      previous,
      next,
    ) {
      final enteredReview =
          previous?.stage != SmartImportStage.reviewing &&
          next.stage == SmartImportStage.reviewing;
      if (enteredReview) {
        Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const TransactionReviewScreen()),
        );
      }
    });

    final state = ref.watch(smartImportControllerProvider);
    final isProcessing = state.stage == SmartImportStage.processing;

    // Without this, backing out mid-OCR leaves `processImages()` running
    // against a controller no widget is listening to anymore — this screen's
    // own `ref.listen` (the only thing that pushes the review screen once
    // extraction finishes) is torn down with it, and reopening Smart Import
    // later calls `reset()` before ever showing what was found, silently
    // discarding it.
    return PopScope(
      canPop: !isProcessing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Import'),
          automaticallyImplyLeading: !isProcessing,
        ),
        body: isProcessing
            ? _ProcessingView(label: state.processingLabel)
            : _PickImagesView(state: state),
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSizes.lg),
          Text(label ?? 'Reading image…', style: context.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PickImagesView extends ConsumerWidget {
  const _PickImagesView({required this.state});

  final SmartImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(smartImportControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How would you like to import transactions?',
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              'Pick a screenshot from your bank, UPI, or wallet app, or scan '
              "a transaction screen or statement with your camera — FlowFi "
              'will pull out the transactions for you to review. Nothing is '
              'saved until you confirm.',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            if (state.errorMessage != null) ...[
              _ErrorBanner(message: state.errorMessage!),
              const SizedBox(height: AppSizes.lg),
            ],
            if (state.images.isNotEmpty)
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: AppSizes.sm,
                    mainAxisSpacing: AppSizes.sm,
                  ),
                  itemCount: state.images.length,
                  itemBuilder: (context, index) => _ImageThumbnail(
                    file: state.images[index],
                    onRemove: () => controller.removeImage(index),
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      state.images.isEmpty
                          ? 'Screenshot / Gallery'
                          : 'Add more',
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => CameraCaptureScreen.show(context),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan with Camera'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            PrimaryButton(
              label: state.images.length > 1
                  ? 'Scan ${state.images.length} images'
                  : 'Scan image',
              onPressed: state.images.isEmpty ? null : controller.processImages,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          child: Image.file(file, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: context.colors.onErrorContainer,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
