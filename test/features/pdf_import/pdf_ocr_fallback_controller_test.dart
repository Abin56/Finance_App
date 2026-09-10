@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/pdf_import/data/services/pdf_file_picker_service.dart';
import 'package:finance_app/features/pdf_import/data/services/pdf_ocr_fallback_service.dart';
import 'package:finance_app/features/pdf_import/data/services/pdf_statement_service.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_open_outcome.dart';
import 'package:finance_app/features/pdf_import/presentation/providers/pdf_import_providers.dart';
import 'package:finance_app/features/pdf_import/presentation/providers/pdf_import_state.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePdfFilePickerService implements PdfFilePickerService {
  _FakePdfFilePickerService(this.outcome);
  final PdfPickOutcome outcome;

  @override
  Future<PdfPickOutcome> pickPdf() async => outcome;
}

/// Always reports the PDF as having no embedded text — the trigger for the
/// controller's OCR fallback path.
class _AlwaysEmptyPdfStatementService implements PdfStatementService {
  @override
  Future<PdfOpenOutcome> open(File file) async =>
      const PdfOpenOutcome.empty();

  @override
  Future<PdfOpenOutcome> openWithPassword(File file, String password) async =>
      const PdfOpenOutcome.empty();
}

/// Records the progress callbacks it was given and returns a canned OCR
/// result (or throws) without touching pdfrx/ML Kit at all — mirrors
/// `_FakePdfStatementService`'s role for the embedded-text path.
class _FakePdfOcrFallbackService implements PdfOcrFallbackService {
  _FakePdfOcrFallbackService({this.result, this.error});

  final PdfExtractionResult? result;
  final Object? error;

  final List<(int, int)> progressCalls = [];

  @override
  Future<PdfExtractionResult> extractViaOcr(
    File file, {
    void Function(int currentPage, int totalPages)? onPageProgress,
  }) async {
    if (onPageProgress != null && result != null) {
      for (var i = 0; i < result!.pageCount; i++) {
        onPageProgress(i + 1, result!.pageCount);
        progressCalls.add((i + 1, result!.pageCount));
      }
    }
    if (error != null) throw error!;
    return result ?? const PdfExtractionResult(pages: []);
  }
}

/// Only resolves once the test explicitly completes [gate] — lets a test
/// control exactly when a simulated OCR scan finishes relative to other
/// controller calls (e.g. `reset()`), to exercise the stale-callback race
/// that a synchronously-resolving fake can't reach.
class _GatedPdfOcrFallbackService implements PdfOcrFallbackService {
  _GatedPdfOcrFallbackService(this.result);

  final PdfExtractionResult result;
  final gate = Completer<void>();

  @override
  Future<PdfExtractionResult> extractViaOcr(
    File file, {
    void Function(int currentPage, int totalPages)? onPageProgress,
  }) async {
    await gate.future;
    return result;
  }
}

PdfTextLine _line(String text, double top, {double left = 0}) {
  return PdfTextLine(
    text: text,
    boundingBox: PdfBoundingBox(
      left: left,
      top: top,
      right: left + 200,
      bottom: top + 12,
    ),
    source: PdfTextSource.ocr,
  );
}

ProviderContainer _buildContainer({
  required PdfPickOutcome pickOutcome,
  required PdfOcrFallbackService ocrFallbackService,
  required SmsInboxDatabase merchantMemoryDb,
}) {
  return ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      currentUserIdProvider.overrideWithValue('test-uid'),
      smsInboxDatabaseProvider.overrideWithValue(merchantMemoryDb),
      pdfFilePickerServiceProvider.overrideWithValue(
        _FakePdfFilePickerService(pickOutcome),
      ),
      pdfStatementServiceProvider.overrideWithValue(
        _AlwaysEmptyPdfStatementService(),
      ),
      pdfOcrFallbackServiceProvider.overrideWithValue(ocrFallbackService),
    ],
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase merchantMemoryDb;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    merchantMemoryDb = await SmsInboxDatabase.openInMemoryForTest();
  });

  group('PdfImportController OCR fallback', () {
    test(
      'a scanned single-page PDF is OCR\'d and reaches reviewing with detected transactions',
      () async {
        final ocrExtraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.ocr,
              lines: [_line('05/09/2026 SWIGGY BANGALORE 420.00', 100)],
            ),
          ],
        );
        final ocrService = _FakePdfOcrFallbackService(result: ocrExtraction);
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('scanned.pdf')),
          ocrFallbackService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
        );
        addTearDown(container.dispose);

        final picked = await container
            .read(pdfImportControllerProvider.notifier)
            .pickFile();

        expect(picked, isTrue);
        final state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.reviewing);
        expect(state.detected, hasLength(1));
        expect(state.detected.single.amount, 420.0);
        expect(
          state.result!.pages.single.source,
          PdfTextSource.ocr,
          reason: 'the extraction result must carry through as OCR-sourced',
        );
      },
    );

    test(
      'a multi-page scanned PDF reports per-page progress and merges all pages',
      () async {
        final ocrExtraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.ocr,
              lines: [_line('05/09/2026 SWIGGY 420.00', 100)],
            ),
            PdfPageResult(
              pageNumber: 2,
              source: PdfTextSource.ocr,
              lines: [_line('06/09/2026 UBER 185.50', 100)],
            ),
            PdfPageResult(
              pageNumber: 3,
              source: PdfTextSource.ocr,
              lines: [_line('07/09/2026 AMAZON 1,299.00', 100)],
            ),
          ],
        );
        final ocrService = _FakePdfOcrFallbackService(result: ocrExtraction);
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('scanned3.pdf')),
          ocrFallbackService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
        );
        addTearDown(container.dispose);

        await container.read(pdfImportControllerProvider.notifier).pickFile();

        expect(ocrService.progressCalls, [(1, 3), (2, 3), (3, 3)]);
        final state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.reviewing);
        expect(state.detected, hasLength(3));
      },
    );

    test(
      'a scanned PDF with no OCR-able text surfaces a plain-language "no transactions" error',
      () async {
        final ocrService = _FakePdfOcrFallbackService(
          result: const PdfExtractionResult(pages: []),
        );
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('blank.pdf')),
          ocrFallbackService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
        );
        addTearDown(container.dispose);

        await container.read(pdfImportControllerProvider.notifier).pickFile();

        final state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.pickingFile);
        expect(state.errorMessage, contains("couldn't find any transactions"));
      },
    );

    test(
      'a rasterization/OCR failure surfaces a plain-language error, never a stack trace',
      () async {
        final ocrService = _FakePdfOcrFallbackService(
          error: Exception('pdfium native failure: 0xdeadbeef'),
        );
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('corrupt_scan.pdf')),
          ocrFallbackService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
        );
        addTearDown(container.dispose);

        await container.read(pdfImportControllerProvider.notifier).pickFile();

        final state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.pickingFile);
        expect(state.errorMessage, contains("couldn't find any transactions"));
        expect(state.errorMessage, isNot(contains('pdfium')));
        expect(state.errorMessage, isNot(contains('0xdeadbeef')));
      },
    );

    test('processingLabel is cleared once OCR fallback finishes', () async {
      final ocrExtraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [_line('05/09/2026 SWIGGY 420.00', 100)],
          ),
        ],
      );
      final ocrService = _FakePdfOcrFallbackService(result: ocrExtraction);
      final container = _buildContainer(
        pickOutcome: PdfPickOutcome.success(File('scanned.pdf')),
        ocrFallbackService: ocrService,
        merchantMemoryDb: merchantMemoryDb,
      );
      addTearDown(container.dispose);

      await container.read(pdfImportControllerProvider.notifier).pickFile();

      expect(container.read(pdfImportControllerProvider).processingLabel, isNull);
    });

    test(
      'a reset while OCR is still running discards that scan\'s result instead '
      'of clobbering the freshly-reset state once it resolves',
      () async {
        final ocrExtraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.ocr,
              lines: [_line('05/09/2026 SWIGGY 420.00', 100)],
            ),
          ],
        );
        final ocrService = _GatedPdfOcrFallbackService(ocrExtraction);
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('scanned.pdf')),
          ocrFallbackService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
        );
        addTearDown(container.dispose);

        final controller = container.read(pdfImportControllerProvider.notifier);
        // Not awaited: this OCR call is left in flight while the user backs
        // out below, mirroring "user resets mid-scan". Pumped through a few
        // microtasks first so `_tryOcrFallback` actually reaches its gated
        // `extractViaOcr` call (and captures its session token) before
        // `reset()` runs — otherwise `reset()` would race ahead of it in the
        // same synchronous turn and bump the token *before* it's captured,
        // defeating the very race this test means to simulate.
        final pickFuture = controller.pickFile();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        controller.reset();
        expect(
          container.read(pdfImportControllerProvider).stage,
          PdfImportStage.pickingFile,
          reason: 'reset() must take effect immediately regardless of the '
              'still-running scan',
        );

        // Let the abandoned scan finish now.
        ocrService.gate.complete();
        await pickFuture;

        final state = container.read(pdfImportControllerProvider);
        expect(
          state.stage,
          PdfImportStage.pickingFile,
          reason: 'the stale OCR result must never resurrect the old session',
        );
        expect(state.detected, isEmpty);
        expect(state.result, isNull);
      },
    );
  });
}
