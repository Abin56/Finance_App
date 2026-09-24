import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/services/camera_permission_service.dart';
import '../../data/services/transaction_ocr_service.dart';
import '../../domain/camera_capture_outcome.dart';
import '../../domain/detected_transaction.dart';
import '../../domain/screenshot_duplicate_detector.dart';
import '../../domain/screenshot_transaction_extractor.dart';
import 'smart_import_state.dart';

/// On-device OCR runs fully offline; the recognizer is a native resource, so
/// it's released via [ref.onDispose] once nothing needs Smart Import anymore.
final transactionOcrServiceProvider = Provider<TransactionOcrService>((ref) {
  final service = MlKitTransactionOcrService();
  ref.onDispose(service.dispose);
  return service;
});

final cameraPermissionServiceProvider = Provider<CameraPermissionService>(
  (ref) => const CameraPermissionService(),
);

final smartImportControllerProvider =
    NotifierProvider<SmartImportController, SmartImportState>(
      SmartImportController.new,
    );

/// Owns one Smart Import session end-to-end: image selection → OCR →
/// extraction → review edits → duplicate re-check → import. Every write
/// still goes through [transactionRepositoryProvider] — this controller
/// never touches Firestore directly.
class SmartImportController extends Notifier<SmartImportState> {
  @override
  SmartImportState build() => const SmartImportState();

  /// Preselects the account this session was opened for (e.g. from an
  /// account's own screen) — a no-op once the user has already picked one.
  void preselectAccount(String? accountId) {
    if (accountId == null || state.accountId != null) return;
    state = state.copyWith(accountId: accountId);
  }

  void setAccount(String accountId) {
    state = state.copyWith(accountId: accountId);
    _recheckDuplicates();
  }

  Future<void> pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
    if (files.isEmpty) return;
    _addImages(files.map((x) => File(x.path)));
  }

  /// Requests camera permission (if needed) and launches the system camera.
  /// Mirrors [pickImages]'s downscaling exactly (`imageQuality: 85`,
  /// `maxWidth: 2000`) — same OCR input regardless of source. Does **not**
  /// add the result to the pending batch: the camera screen shows its own
  /// Retake/Use Photo confirmation first, via [confirmCapturedImage].
  Future<CameraCaptureOutcome> captureFromCamera() async {
    final permission = await ref
        .read(cameraPermissionServiceProvider)
        .ensureGranted();
    if (permission == CameraPermissionResult.permanentlyDenied) {
      return const CameraCaptureOutcome.permissionPermanentlyDenied();
    }
    if (permission == CameraPermissionResult.denied) {
      return const CameraCaptureOutcome.permissionDenied();
    }

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) return const CameraCaptureOutcome.cancelled();
      return CameraCaptureOutcome.success(File(picked.path));
    } on PlatformException catch (e) {
      // A defensive fallback alongside the proactive `permission_handler`
      // check above — covers the OS's own runtime dialog denying access in
      // a way our own pre-check didn't already catch.
      if (e.code == 'camera_access_denied') {
        return const CameraCaptureOutcome.permissionDenied();
      }
      return const CameraCaptureOutcome.unavailable();
    } catch (_) {
      return const CameraCaptureOutcome.unavailable();
    }
  }

  /// The user tapped "Use Photo" — from here on this image is
  /// indistinguishable from a gallery pick; [processImages] runs the exact
  /// same OCR → extraction → review → duplicate-check pipeline regardless
  /// of source.
  void confirmCapturedImage(File file) => _addImages([file]);

  /// A capture the user chose not to use (retake, or backed out of the
  /// preview) — deleted immediately rather than waiting for [reset], since
  /// it never entered the pending batch and nothing else references it.
  void discardCapturedImage(File file) => _deleteFiles([file]);

  void _addImages(Iterable<File> files) {
    state = state.copyWith(
      images: [...state.images, ...files],
      clearErrorMessage: true,
    );
  }

  void removeImage(int index) {
    final images = [...state.images]..removeAt(index);
    final removed = state.images[index];
    state = state.copyWith(images: images);
    _deleteFiles([removed]);
  }

  /// Clears any in-progress session. Also best-effort deletes any picked or
  /// captured images that were never scanned (e.g. the user picked images
  /// then navigated away) — financial screenshots/photos shouldn't linger
  /// in the app's picker cache any longer than necessary.
  void reset() {
    _deleteFiles(state.images);
    state = const SmartImportState();
  }

  /// Best-effort cleanup of picked-image temp files. Never lets a deletion
  /// failure (file already gone, permission hiccup) surface as an error —
  /// this is housekeeping, not a correctness requirement, and the OS will
  /// eventually reclaim its own cache directory regardless.
  void _deleteFiles(List<File> files) {
    for (final file in files) {
      // Fire-and-forget: intentionally not awaited so callers (all of which
      // are synchronous UI actions) never block on filesystem cleanup.
      Future(() async {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best-effort only — see the doc comment above.
        }
      });
    }
  }

  Future<void> processImages() async {
    if (state.images.isEmpty) return;

    state = state.copyWith(
      stage: SmartImportStage.processing,
      clearErrorMessage: true,
      processingLabel: state.images.length == 1
          ? 'Reading image…'
          : 'Reading image 1 of ${state.images.length}…',
    );

    final ocrService = ref.read(transactionOcrServiceProvider);
    const extractor = ScreenshotTransactionExtractor();
    final detected = <DetectedTransaction>[];
    var anyTextFound = false;
    // One corrupt/unsupported image must never discard transactions already
    // pulled from other images in the same batch — each image's OCR call is
    // caught individually, that image is skipped, and the loop continues.
    // Only reported to the user if it left the batch with nothing at all
    // (see `allImagesFailed` below); a partial failure among an otherwise
    // successful batch is silent by design, matching how a single failed
    // import row doesn't block the rest of the batch either.
    var failedImageCount = 0;

    for (var i = 0; i < state.images.length; i++) {
      state = state.copyWith(
        processingLabel: 'Reading image ${i + 1} of ${state.images.length}…',
      );
      try {
        final ocrResult = await ocrService.extractText(state.images[i]);
        if (ocrResult.hasText) anyTextFound = true;
        detected.addAll(extractor.extract(ocrResult, sourceImageIndex: i));
      } catch (_) {
        failedImageCount++;
      }
    }

    final allImagesFailed = failedImageCount == state.images.length;
    if (allImagesFailed) {
      state = state.copyWith(
        stage: SmartImportStage.pickingImages,
        clearProcessingLabel: true,
        errorMessage: state.images.length == 1
            ? 'We had trouble reading that image. Please try again.'
            : 'We had trouble reading these images. Please try again.',
      );
      return;
    }

    if (!anyTextFound) {
      state = state.copyWith(
        stage: SmartImportStage.pickingImages,
        clearProcessingLabel: true,
        errorMessage:
            "We couldn't read any transaction information from this image.\n\nTry a clearer image.",
      );
      return;
    }

    if (detected.isEmpty) {
      state = state.copyWith(
        stage: SmartImportStage.pickingImages,
        clearProcessingLabel: true,
        errorMessage:
            'No transactions found.\n\nMake sure the image contains transaction details.',
      );
      return;
    }

    _applyCategorySuggestions(detected);
    ScreenshotDuplicateDetector.apply(
      detected,
      ref.read(transactionsStreamProvider).value ?? const [],
      accountId: state.accountId,
    );

    // The raw screenshots are never needed again once OCR has read them —
    // only the extracted text carries forward into review — and we're
    // leaving the picker screen for good on this path, so this is the one
    // safe point to delete them: no UI still shows their thumbnails, and
    // there's no "try again with the same images" path left that needs them.
    final scannedImages = state.images;
    state = state.copyWith(
      stage: SmartImportStage.reviewing,
      detected: detected,
      images: const [],
      clearProcessingLabel: true,
      // A partial failure (some, not all, images unreadable) still reaches
      // review with whatever succeeded — surfaced as a plain-language note
      // rather than silently under-counting, so the user knows why they see
      // fewer transactions than screenshots.
      errorMessage: failedImageCount > 0
          ? (failedImageCount == 1
                ? "Couldn't read 1 of ${state.images.length} images. The rest were processed normally."
                : "Couldn't read $failedImageCount of ${state.images.length} images. The rest were processed normally.")
          : null,
    );
    _deleteFiles(scannedImages);
  }

  void _applyCategorySuggestions(List<DetectedTransaction> detected) {
    final categories = ref.read(categoriesStreamProvider).value ?? const [];
    final suggester = ref.read(merchantCategorySuggesterProvider);
    for (final row in detected) {
      final type = row.type ?? TransactionType.expense;
      final suggestion = suggester.suggest(
        merchant: row.rawDescription,
        transactionType: type,
        categories: categories,
      );
      if (suggestion != null) {
        row.categoryId = suggestion.categoryId;
        row.categorySuggestionSource = suggestion.source;
      }
    }
  }

  void _recheckDuplicates() {
    final updated = [...state.detected];
    ScreenshotDuplicateDetector.apply(
      updated,
      ref.read(transactionsStreamProvider).value ?? const [],
      accountId: state.accountId,
    );
    state = state.copyWith(detected: updated);
  }

  void toggleSelected(String id, bool selected) {
    _mutate(id, (row) => row.isSelected = selected);
  }

  void selectAll() {
    final updated = [...state.detected];
    for (final row in updated) {
      row.isSelected = true;
    }
    state = state.copyWith(detected: updated);
  }

  void deselectAll() {
    final updated = [...state.detected];
    for (final row in updated) {
      row.isSelected = false;
    }
    state = state.copyWith(detected: updated);
  }

  void skipDuplicate(String id) {
    _mutate(id, (row) {
      row.duplicateAcknowledged = false;
      row.isSelected = false;
    });
  }

  void importDuplicateAnyway(String id) {
    _mutate(id, (row) {
      row.duplicateAcknowledged = true;
      row.isSelected = true;
    });
  }

  void updateTransaction(
    String id, {
    DateTime? date,
    String? description,
    double? amount,
    TransactionType? type,
    String? categoryId,
  }) {
    _mutate(id, (row) {
      if (date != null) row.date = date;
      if (description != null) row.rawDescription = description;
      if (amount != null) row.amount = amount;
      if (type != null) row.type = type;
      if (categoryId != null) row.categoryId = categoryId;
    });
    _recheckDuplicates();
  }

  void removeTransaction(String id) {
    state = state.copyWith(
      detected: state.detected.where((d) => d.id != id).toList(),
    );
  }

  void _mutate(String id, void Function(DetectedTransaction row) apply) {
    final updated = [...state.detected];
    final row = updated.firstWhere((d) => d.id == id);
    apply(row);
    state = state.copyWith(detected: updated);
  }

  /// Imports every selected, non-duplicate, valid row through the same
  /// [TransactionRepository.createTransaction] manual entry and SMS import
  /// use. Writes run sequentially (never `Future.wait`) so a failure partway
  /// through never leaves an inconsistent burst of balance adjustments —
  /// same reasoning as `SmsBulkConverter`. Already-imported rows are skipped
  /// unconditionally, so calling this again after a partial failure can
  /// never create a duplicate for anything that already succeeded.
  Future<void> import() async {
    // Cheap, explicit reentrancy guard — makes "a double-tap can't start a
    // second concurrent import" true by construction rather than relying on
    // the button being visually hidden once `stage` flips (which is also
    // true, but shouldn't be the *only* thing preventing a double-write).
    if (state.stage == SmartImportStage.importing) return;

    final accountId = state.accountId;
    if (accountId == null) return;

    // `TransactionRepository.createTransaction` writes the transaction
    // document before it looks up the account to adjust its balance, so a
    // deleted-account failure would otherwise leave an orphaned, un-adjusted
    // transaction behind — and since the row's `isImported` never gets set
    // in that case, a retry would create a second one. Checking here, before
    // any write, keeps that failure mode from ever reaching the repository.
    final accountStillExists =
        (ref.read(accountsStreamProvider).value ?? const []).any(
          (a) => a.id == accountId,
        );
    if (!accountStillExists) {
      state = state.copyWith(
        stage: SmartImportStage.reviewing,
        errorMessage:
            'That account no longer exists. Please choose another one.',
      );
      return;
    }

    // Re-check duplicates against the latest Firestore snapshot right
    // before writing — protects a retried/resumed import from creating a
    // transaction that a previous attempt (or another device) already did.
    final freshDetected = [...state.detected];
    ScreenshotDuplicateDetector.apply(
      freshDetected,
      ref.read(transactionsStreamProvider).value ?? const [],
      accountId: accountId,
    );
    state = state.copyWith(detected: freshDetected);

    final candidates = freshDetected
        .where((d) => d.isSelected && !d.isImported)
        .toList();
    final toImport = candidates
        .where((d) => !d.isDuplicate || d.duplicateAcknowledged)
        .toList();
    final skippedDuplicates = candidates.length - toImport.length;

    state = state.copyWith(
      stage: SmartImportStage.importing,
      importProgress: (0, toImport.length),
    );

    final repository = ref.read(transactionRepositoryProvider);
    var imported = 0;
    var failed = 0;

    for (var i = 0; i < toImport.length; i++) {
      final row = toImport[i];
      state = state.copyWith(importProgress: (i, toImport.length));

      if (!row.hasRequiredFields || row.categoryId == null) {
        failed++;
        continue;
      }

      try {
        await repository.createTransaction(
          type: row.type ?? TransactionType.expense,
          amount: row.amount!,
          dateTime: row.date!,
          accountId: accountId,
          categoryId: row.categoryId!,
          description: row.description,
          source: 'screenshot',
        );
        row.isImported = true;
        row.isSelected = false;
        imported++;

        // Learn from this choice only after the real save succeeded —
        // same after-the-fact-learning rule `completeSmsImport` follows.
        await ref
            .read(merchantMemoriesProvider.notifier)
            .record(
              merchant: row.rawDescription,
              transactionType: row.type ?? TransactionType.expense,
              categoryId: row.categoryId!,
            );
      } catch (_) {
        failed++;
      }
    }

    state = state.copyWith(
      stage: SmartImportStage.done,
      clearImportProgress: true,
      detected: [...state.detected],
      importResult: ImportSummary(
        imported: imported,
        skippedDuplicates: skippedDuplicates,
        failed: failed,
      ),
    );
  }

  /// Re-attempts the import for whatever wasn't imported last time
  /// (skipped-as-duplicate rows stay skipped unless the user re-selects
  /// them; failed rows are retried automatically since they're still
  /// selected and not yet marked imported).
  Future<void> retryImport() => import();
}
