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

  /// A minimum character count per page, on average, below which embedded
  /// text is treated as noise (a stray watermark, a single page number, a
  /// PDF producer's metadata leaking into the text layer) rather than real
  /// statement content — see [looksLikeScannedDocument].
  ///
  /// Deliberately very low: this only needs to catch "basically nothing but
  /// a character or two" pages (a lone digit, a single symbol) — anything
  /// resembling even one short real word or a terse transaction line must
  /// never trip this, since distinguishing a sparse statement from a dense
  /// one is [PdfTransactionParser]'s job, not this heuristic's. A higher
  /// threshold risks misrouting a real, if brief, statement page through
  /// unnecessary OCR — worse than the reverse, since OCR is slower and
  /// strictly less reliable than text that was already extracted cleanly.
  static const int _meaningfulCharsPerPageThreshold = 4;

  /// Whether this extraction looks like it came from a scanned/photographed
  /// statement with no real embedded text layer, as opposed to a statement
  /// with genuinely little text on some pages (a short addendum page, a
  /// mostly-blank final page). Never trips just because total character
  /// count is small — a PDF with one dense page and several blank ones must
  /// not be misclassified as scanned, so this checks total characters across
  /// the whole document against a per-page-scaled floor, not a single
  /// absolute cutoff.
  ///
  /// This is a conservative, testable heuristic — not a certainty. Its
  /// scope is deliberately narrow: it's used only to decide whether OCR
  /// fallback is worth attempting when embedded-text extraction already
  /// found (per [hasAnyText]) either nothing, or so little that it's
  /// unlikely to be genuine statement content (e.g. a single stray
  /// character left by a PDF producer's metadata).
  bool get looksLikeScannedDocument {
    if (pages.isEmpty) return false;
    if (!hasAnyText) return true;

    final totalChars = pages.fold<int>(
      0,
      (sum, page) => sum + page.fullText.trim().length,
    );
    final floor = _meaningfulCharsPerPageThreshold * pages.length;
    return totalChars < floor;
  }
}
