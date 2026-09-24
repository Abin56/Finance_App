import 'pdf_extraction_result.dart';

/// One line reconstructed at a specific vertical position on a page, with
/// the page number it came from — the PDF-layout equivalent of
/// `ScreenshotTransactionExtractor`'s `_VisualRow`, extended with a page
/// number because a statement PDF (unlike a single screenshot) spans many
/// pages and later stages need to know which page a row came from.
class PdfStatementRow {
  const PdfStatementRow({
    required this.text,
    required this.pageNumber,
    required this.top,
    required this.columnTexts,
  });

  final String text;
  final int pageNumber;
  final double top;

  /// The row's text lines still separated by horizontal position
  /// (left-to-right), before being joined into [text]. Kept around so the
  /// parser can apply column-aware heuristics (e.g. "the last column on a
  /// balance-heavy row is very likely the running balance") without having
  /// to re-derive column boundaries from scratch.
  final List<String> columnTexts;
}

/// One candidate transaction's worth of statement rows, grouped by
/// [PdfLayoutReconstructor] — mirrors `_Block` in
/// `ScreenshotTransactionExtractor`/`PasteTransactionExtractor`, extended
/// with page numbers since a block can (rarely) straddle a page break.
class PdfStatementBlock {
  PdfStatementBlock();

  final List<PdfStatementRow> rows = [];

  String get combinedText => rows.map((r) => r.text).join(' ');
}

/// Turns a [PdfExtractionResult] (Phase 1's raw per-page text + bounding
/// boxes) into a flat, cleaned list of [PdfStatementRow]s ready for
/// transaction parsing — reconstructing visual rows from bounding boxes
/// (same technique `ScreenshotTransactionExtractor` uses for OCR lines),
/// stripping repeated page headers/footers, and grouping rows into
/// candidate transaction blocks so a multi-line description or a
/// date-at-the-end layout still produces one block per transaction.
///
/// Deliberately bank-agnostic: nothing here matches on a specific bank's
/// column names or wording. It only uses generic structural signals every
/// tabular bank statement shares — rows are laid out at consistent
/// y-positions per page, and a parseable date marks where a new transaction
/// record most likely starts.
class PdfLayoutReconstructor {
  const PdfLayoutReconstructor();

  /// A line of text repeated verbatim on at least this many pages (and on
  /// more than half of all pages) is treated as boilerplate — a running
  /// header/footer ("Statement of Account", "Page X of Y", a bank's
  /// address block) — rather than a transaction row. Requires at least 2
  /// pages so a single-page statement never has anything stripped by this
  /// rule (nothing on one page can "repeat").
  static const int _minRepeatCountForBoilerplate = 2;

  List<PdfStatementRow> reconstructRows(PdfExtractionResult extraction) {
    final boilerplate = _detectBoilerplateLines(extraction);
    final rows = <PdfStatementRow>[];
    for (final page in extraction.pages) {
      rows.addAll(_reconstructPageRows(page, boilerplate));
    }
    return rows;
  }

  /// Finds lines of text (normalized: trimmed + whitespace-collapsed) that
  /// recur across a majority of pages — the hallmark of a running
  /// header/footer rather than a one-off transaction row. A statement's
  /// column header row ("Date | Description | Amount | Balance") is
  /// intentionally caught by this too: it carries no parseable amount of
  /// its own and would otherwise survive as a bogus needs-review block on
  /// every page.
  Set<String> _detectBoilerplateLines(PdfExtractionResult extraction) {
    if (extraction.pages.length < _minRepeatCountForBoilerplate) return {};

    final countByNormalized = <String, int>{};
    for (final page in extraction.pages) {
      final seenOnThisPage = <String>{};
      for (final line in page.lines) {
        final normalized = _normalizeForRepeatDetection(line.text);
        if (normalized.isEmpty) continue;
        seenOnThisPage.add(normalized);
      }
      for (final normalized in seenOnThisPage) {
        countByNormalized[normalized] = (countByNormalized[normalized] ?? 0) + 1;
      }
    }

    final threshold = (extraction.pages.length / 2).ceil();
    return countByNormalized.entries
        .where(
          (e) => e.value >= _minRepeatCountForBoilerplate && e.value >= threshold,
        )
        .map((e) => e.key)
        .toSet();
  }

  String _normalizeForRepeatDetection(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  List<PdfStatementRow> _reconstructPageRows(
    PdfPageResult page,
    Set<String> boilerplate,
  ) {
    final lines = [...page.lines]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    if (lines.isEmpty) return const [];

    final heights =
        lines.map((l) => l.boundingBox.height).where((h) => h > 0).toList()
          ..sort();
    final medianHeight = heights.isEmpty ? 10.0 : heights[heights.length ~/ 2];
    final mergeThreshold = medianHeight * 0.6;

    final grouped = <List<int>>[];
    for (var i = 0; i < lines.length; i++) {
      final centerY = lines[i].boundingBox.centerY;
      if (grouped.isNotEmpty) {
        final lastGroup = grouped.last;
        final avgCenterY =
            lastGroup
                .map((idx) => lines[idx].boundingBox.centerY)
                .reduce((a, b) => a + b) /
            lastGroup.length;
        if ((centerY - avgCenterY).abs() <= mergeThreshold) {
          lastGroup.add(i);
          continue;
        }
      }
      grouped.add([i]);
    }

    final rows = <PdfStatementRow>[];
    for (final group in grouped) {
      final ordered = [...group]
        ..sort(
          (a, b) =>
              lines[a].boundingBox.left.compareTo(lines[b].boundingBox.left),
        );
      final columnTexts = ordered
          .map((idx) => lines[idx].text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (columnTexts.isEmpty) continue;

      final text = columnTexts.join('  ').trim();
      if (boilerplate.contains(_normalizeForRepeatDetection(text))) continue;

      final top = group
          .map((idx) => lines[idx].boundingBox.top)
          .reduce((a, b) => a < b ? a : b);
      rows.add(
        PdfStatementRow(
          text: text,
          pageNumber: page.pageNumber,
          top: top,
          columnTexts: columnTexts,
        ),
      );
    }
    return rows;
  }
}
