import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../domain/pdf_extraction_result.dart';
import '../../domain/pdf_open_outcome.dart';

/// Opens (decrypting if needed) and extracts text from a statement PDF.
///
/// Kept as an interface — never referenced directly by the parser or review
/// UI, mirroring `TransactionOcrService` — so the PDF vendor could be swapped
/// without touching any parsing logic. Wraps Syncfusion's `PdfDocument`
/// entirely: nothing above this layer imports `package:syncfusion_flutter_pdf`.
abstract class PdfStatementService {
  /// Attempts to open [file] with no password. Returns
  /// [PdfOpenStatus.passwordRequired] if the PDF is encrypted, without ever
  /// trying a guessed/empty password against it.
  Future<PdfOpenOutcome> open(File file);

  /// Attempts to open [file] using [password]. Returns
  /// [PdfOpenStatus.incorrectPassword] if Syncfusion rejects it — never
  /// retried automatically, never logged.
  Future<PdfOpenOutcome> openWithPassword(File file, String password);
}

class SyncfusionPdfStatementService implements PdfStatementService {
  @override
  Future<PdfOpenOutcome> open(File file) => _open(file, password: null);

  @override
  Future<PdfOpenOutcome> openWithPassword(File file, String password) =>
      _open(file, password: password);

  Future<PdfOpenOutcome> _open(File file, {required String? password}) async {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return const PdfOpenOutcome.invalidPdf();
    }

    if (bytes.isEmpty) return const PdfOpenOutcome.invalidPdf();

    PdfDocument document;
    try {
      document = PdfDocument(inputBytes: bytes, password: password);
    } on ArgumentError catch (e) {
      // Syncfusion throws the same ArgumentError (message mentions the
      // password being invalid) whether no password was supplied for an
      // encrypted PDF or a wrong one was — distinguished here by whether the
      // caller told us they were actually attempting a password, never by
      // guessing from the exception text alone (never logged either way, it
      // may echo back the attempted password).
      if (_looksLikePasswordError(e)) {
        return password == null
            ? const PdfOpenOutcome.passwordRequired()
            : const PdfOpenOutcome.incorrectPassword();
      }
      return const PdfOpenOutcome.invalidPdf();
    } on FormatException {
      return const PdfOpenOutcome.invalidPdf();
    } catch (_) {
      // Any other parser-internal failure (Syncfusion's PDF parser throws a
      // mix of its own internal error types for malformed structure) reads
      // to the user as an unreadable file, never a stack trace.
      return const PdfOpenOutcome.invalidPdf();
    }

    try {
      if (document.pages.count == 0) {
        return const PdfOpenOutcome.empty();
      }

      final pages = <PdfPageResult>[];
      for (var i = 0; i < document.pages.count; i++) {
        final extractor = PdfTextExtractor(document);
        final textLines = extractor.extractTextLines(
          startPageIndex: i,
          endPageIndex: i,
        );
        final lines = [
          for (final line in textLines)
            if (line.text.trim().isNotEmpty)
              PdfTextLine(
                text: line.text,
                boundingBox: PdfBoundingBox(
                  left: line.bounds.left,
                  top: line.bounds.top,
                  right: line.bounds.right,
                  bottom: line.bounds.bottom,
                ),
                source: PdfTextSource.embedded,
              ),
        ];
        pages.add(
          PdfPageResult(
            pageNumber: i + 1,
            lines: lines,
            source: PdfTextSource.embedded,
          ),
        );
      }

      final result = PdfExtractionResult(pages: pages);
      if (!result.hasAnyText) {
        // Not necessarily empty — likely a scanned/image-only PDF with no
        // embedded text layer at all. Reported as `empty` here;
        // `PdfImportController` is what actually handles this case, via
        // `PdfOcrFallbackService` rasterizing pages and running OCR instead
        // of relying on this text path. Deliberately not folded into this
        // service: it stays scoped to "read the PDF's own embedded text",
        // never importing `pdfrx` or an OCR engine itself.
        return const PdfOpenOutcome.empty();
      }
      // A page or two with genuinely little text (a short addendum, a
      // mostly-blank closing page) must not be misclassified as scanned —
      // `looksLikeScannedDocument` checks total character volume against a
      // conservative per-page floor rather than tripping on any single
      // sparse page, so a real (if terse) statement always takes this path
      // rather than being needlessly routed through OCR.
      if (result.looksLikeScannedDocument) {
        return const PdfOpenOutcome.empty();
      }
      return PdfOpenOutcome.success(result);
    } finally {
      document.dispose();
    }
  }

  bool _looksLikePasswordError(ArgumentError e) {
    final message = e.message;
    if (message is! String) return false;
    return message.toLowerCase().contains('password');
  }
}
