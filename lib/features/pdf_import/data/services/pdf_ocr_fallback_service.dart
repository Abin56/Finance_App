import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../smart_import/data/services/transaction_ocr_service.dart';
import '../../domain/pdf_extraction_result.dart';

/// Renders each page of a scanned/image-only statement PDF (one with no
/// embedded text layer at all — see [PdfStatementService]'s "empty" result)
/// to an image and runs OCR on it, producing a [PdfExtractionResult] shaped
/// exactly like the embedded-text path's — same [PdfTextLine]/[PdfBoundingBox]
/// structure, just tagged [PdfTextSource.ocr] — so [PdfLayoutReconstructor]
/// and [PdfTransactionParser] need no changes at all to consume either kind
/// of source. Kept as an interface for the same reason [PdfStatementService]
/// and [TransactionOcrService] are: nothing above this layer depends on
/// `pdfrx` or the OCR vendor directly.
abstract class PdfOcrFallbackService {
  /// Renders and OCRs every page of [file], reporting progress via
  /// [onPageProgress] (1-indexed current page, total page count) so the
  /// caller can surface "Scanning page 2 of 8…" — never technical
  /// rasterization/OCR terminology. Returns an empty-pages result (never
  /// throws) if the PDF has zero pages or every page fails to render.
  Future<PdfExtractionResult> extractViaOcr(
    File file, {
    void Function(int currentPage, int totalPages)? onPageProgress,
  });
}

/// Renders pages via `pdfrx` (a separate PDF engine from Syncfusion, used
/// here purely for rasterization since Syncfusion's module in this project
/// has no render-to-image API) and reuses [TransactionOcrService] — the same
/// on-device ML Kit wrapper Screenshot Import already uses — for OCR, rather
/// than wiring up a second OCR engine. The image never leaves the device.
class PdfrxOcrFallbackService implements PdfOcrFallbackService {
  PdfrxOcrFallbackService(this._ocrService);

  final TransactionOcrService _ocrService;

  /// Target render resolution. 220 DPI is a middle ground: high enough for
  /// ML Kit to reliably read statement-sized print, low enough that an
  /// 8-page statement doesn't hold multiple huge bitmaps in memory at once
  /// (pages are rendered and OCR'd one at a time — see [extractViaOcr] — so
  /// only one page's image exists in memory at any moment regardless of
  /// this value, but a needlessly high DPI still costs render time and a
  /// larger single-page buffer).
  static const double _renderDpi = 220;

  @override
  Future<PdfExtractionResult> extractViaOcr(
    File file, {
    void Function(int currentPage, int totalPages)? onPageProgress,
  }) async {
    final bytes = Uint8List.fromList(await file.readAsBytes());
    // A brand-new, independent handle from Syncfusion's — `pdfrx` never
    // touches the `PdfDocument` `SyncfusionPdfStatementService` already
    // opened and disposed; this method is only ever reached after that
    // path already gave up (`PdfOpenStatus.empty`), so there's no handle
    // reuse to worry about, only re-reading the same bytes from disk.
    final document = await pdfrx.PdfDocument.openData(
      bytes,
      sourceName: file.path,
    );

    try {
      final pageCount = document.pages.length;
      if (pageCount == 0) return const PdfExtractionResult(pages: []);

      final pages = <PdfPageResult>[];
      for (var i = 0; i < pageCount; i++) {
        onPageProgress?.call(i + 1, pageCount);
        final page = document.pages[i];
        final lines = await _ocrPage(page);
        pages.add(
          PdfPageResult(
            pageNumber: i + 1,
            lines: lines,
            source: PdfTextSource.ocr,
          ),
        );
      }
      return PdfExtractionResult(pages: pages);
    } finally {
      await document.dispose();
    }
  }

  Future<List<PdfTextLine>> _ocrPage(pdfrx.PdfPage page) async {
    final scale = _renderDpi / 72;
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (image == null) return const [];

    File? tempFile;
    try {
      final uiImage = await image.createImage();
      try {
        final pngBytes = await uiImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (pngBytes == null) return const [];

        tempFile = await _writeTempPng(pngBytes.buffer.asUint8List());
        final ocrResult = await _ocrService.extractText(tempFile);

        return [
          for (final line in ocrResult.lines)
            if (line.text.trim().isNotEmpty)
              PdfTextLine(
                text: line.text,
                boundingBox: PdfBoundingBox(
                  left: line.boundingBox.left,
                  top: line.boundingBox.top,
                  right: line.boundingBox.right,
                  bottom: line.boundingBox.bottom,
                ),
                source: PdfTextSource.ocr,
              ),
        ];
      } finally {
        uiImage.dispose();
      }
    } finally {
      image.dispose();
      // Never left behind — a scanned bank statement's rendered page image
      // is exactly the kind of financial content that must not linger on
      // disk any longer than the single OCR call that needs it.
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<File> _writeTempPng(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/pdf_ocr_page_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes);
    return file;
  }
}
