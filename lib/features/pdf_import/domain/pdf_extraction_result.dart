/// Where one [PdfTextLine] came from — a bank statement PDF's own embedded
/// text layer, or OCR run on a rasterized page image (scanned/photographed
/// statement with no selectable text). Layout reconstruction and the
/// transaction parser (later phases) can use this to be more conservative
/// about OCR-sourced lines, which are noisier than a PDF's native text.
enum PdfTextSource { embedded, ocr }

/// A line's position on its page, in PDF point space (embedded text) or the
/// rendered image's pixel space (OCR) — never mixed within the same page.
/// Mirrors `OcrBoundingBox` in `smart_import/domain/ocr_result.dart`
/// deliberately, so later layout-reconstruction code can treat a PDF page's
/// lines the same way the screenshot extractor already treats OCR lines.
class PdfBoundingBox {
  const PdfBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
  double get width => right - left;
}

/// One line of text extracted from a PDF page, plus where it sits on the
/// page. Positional data is kept (not thrown away) because bank statement
/// tables depend heavily on column alignment for later layout
/// reconstruction — see the feature's architecture notes.
class PdfTextLine {
  const PdfTextLine({
    required this.text,
    required this.boundingBox,
    required this.source,
  });

  final String text;
  final PdfBoundingBox boundingBox;
  final PdfTextSource source;
}

/// Everything extracted from one page of a statement PDF.
class PdfPageResult {
  const PdfPageResult({
    required this.pageNumber,
    required this.lines,
    required this.source,
  });

  /// 1-indexed, matching how page numbers are shown to the user.
  final int pageNumber;

  final List<PdfTextLine> lines;

  /// Whether this page's [lines] came from the PDF's embedded text layer or
  /// from OCR — a page-level PDF can mix pages of each within one document
  /// (e.g. a statement with one scanned addendum page).
  final PdfTextSource source;

  String get fullText => lines.map((l) => l.text).join('\n');

  bool get hasText => lines.isNotEmpty && fullText.trim().isNotEmpty;
}

/// The full result of extracting text from a statement PDF, across all
/// pages. This is Phase 1's output — later phases turn this into normalized
/// transaction rows the same way `OcrResult` feeds
/// `ScreenshotTransactionExtractor` today.
class PdfExtractionResult {
  const PdfExtractionResult({required this.pages});

  final List<PdfPageResult> pages;

  int get pageCount => pages.length;

  bool get hasAnyText => pages.any((p) => p.hasText);

  String get fullText => pages.map((p) => p.fullText).join('\n');
}
