import '../../smart_import/domain/smart_import_amount_parser.dart';
import '../../smart_import/domain/smart_import_date_parser.dart';
import 'pdf_layout_reconstructor.dart';

/// Finds the contiguous run(s) of [PdfStatementRow]s that actually make up
/// a statement's transaction table, so header/account-summary content
/// before it and trailing legal/T&C content after it — on the same page or
/// on separate pages — never reach [PdfTransactionParser]'s block grouper
/// in the first place.
///
/// Runs between [PdfLayoutReconstructor] and the block grouper: it consumes
/// the same flat, boilerplate-stripped row list layout reconstruction
/// already produces and returns a filtered subset of it. It never touches
/// text content beyond the same generic structural signals the rest of PDF
/// import already relies on ([SmartImportDateParser],
/// [SmartImportAmountParser]) — nothing here matches on a specific bank's
/// wording, page numbers, or coordinates.
///
/// Deliberately conservative: if the document's structure doesn't produce
/// at least one confident region *anywhere*, [detect] returns `null` and
/// the caller must fall back to parsing every row, unfiltered — exactly
/// today's behavior. This protects every layout that predates this
/// detector (headerless statements, date-last/receipt-style single
/// transactions, small synthetic fixtures) from ever being reduced to zero
/// detected transactions just because no header or dense run was found.
abstract class PdfTransactionRegionDetector {
  PdfTransactionRegionDetector._();

  // Generic column-header vocabulary shared by most tabular bank/card
  // statements — not tied to any one issuer's wording. A header row is
  // recognized by carrying at least two of these as whole words, since any
  // one alone ("Date", "Amount") is common enough in ordinary prose to be a
  // false positive on its own.
  static final RegExp _headerWordPattern = RegExp(
    r'\b(date|amount|transaction|details|description|narration|'
    r'particulars|debit|credit|balance)\b',
    caseSensitive: false,
  );

  // A trailing 1-2 letter direction code directly after an amount-shaped
  // figure ("420.00 D", "1,250.00 DR", "55,000.00 CR", "2,116.86 M") — a
  // strong, generic structural signal of a real transaction row on
  // statements that encode direction this way, independent of any
  // particular bank's terminology.
  static final RegExp _trailingDirectionCodePattern = RegExp(
    r'[\d,.]\s*\)?\s*[A-Za-z]{1,2}\s*$',
  );

  /// Consecutive non-transaction-shaped rows tolerated within an open
  /// region before it's considered to have ended — covers a wrapped
  /// second description line (the existing multi-line-description fixture
  /// has exactly one such row) without letting a long run of unrelated
  /// prose (account summary, legal text) stay attached to the region.
  static const int _maxGapRows = 1;

  /// Consecutive transaction-shaped rows required to open a region purely
  /// on density, with no header present — this is what lets a headerless,
  /// tightly-packed date-first table still be detected.
  static const int _minDensityRun = 3;

  /// Returns the subset of [rows] that fall inside a detected transaction
  /// region, in original order, or `null` if no region could be confidently
  /// identified anywhere in the document — callers must treat `null` as
  /// "parse every row, unfiltered" rather than as "zero transactions."
  static List<PdfStatementRow>? detect(
    List<PdfStatementRow> rows, {
    DateTime? referenceDate,
  }) {
    if (rows.isEmpty) return null;
    final reference = referenceDate ?? DateTime.now();

    final byPage = <int, List<PdfStatementRow>>{};
    for (final row in rows) {
      byPage.putIfAbsent(row.pageNumber, () => []).add(row);
    }

    final kept = <PdfStatementRow>[];
    var anyRegionFound = false;
    for (final pageNumber in byPage.keys.toList()..sort()) {
      final pageRows = byPage[pageNumber]!;
      final regionRows = _detectPageRegion(pageRows, reference);
      if (regionRows != null) {
        anyRegionFound = true;
        kept.addAll(regionRows);
      }
    }

    return anyRegionFound ? kept : null;
  }

  static List<PdfStatementRow>? _detectPageRegion(
    List<PdfStatementRow> pageRows,
    DateTime reference,
  ) {
    final shapes = pageRows
        .map((row) => _classify(row, reference))
        .toList(growable: false);

    int? regionStart;
    int? regionEnd;
    var gapRun = 0;

    for (var i = 0; i < pageRows.length; i++) {
      final isTransactionShaped = shapes[i] == _RowShape.transactionShaped;

      if (isTransactionShaped) {
        if (regionStart == null) {
          final headerAnchored =
              i > 0 && shapes[i - 1] == _RowShape.tableHeaderShaped;
          final densityAnchored = _hasDensityRun(shapes, i);
          if (headerAnchored || densityAnchored) {
            regionStart = i;
          }
        }
        if (regionStart != null) {
          regionEnd = i;
          gapRun = 0;
        }
        continue;
      }

      if (regionStart == null) continue;

      // A header for a *different* table (e.g. a fee schedule) appearing
      // after the region has already started, with no transaction-shaped
      // rows immediately following it, closes the region here rather than
      // tolerating it as a gap row.
      if (shapes[i] == _RowShape.tableHeaderShaped &&
          !_hasDensityRun(shapes, i + 1)) {
        break;
      }

      // A row carrying a date-at-start or an amount on its own — just not
      // both together, and with no trailing direction code — is very
      // likely one fragment of a date-last transaction block split across
      // several rows (description, then amount, then a trailing date-only
      // row), not genuine non-transaction prose. Only a row with *neither*
      // signal (the real signature of account-summary or legal text) counts
      // toward the gap that closes a region — this is what lets a
      // multi-row date-last block stay inside the region without loosening
      // the gap tolerance in a way that would re-admit real boilerplate.
      if (shapes[i] == _RowShape.dateOrAmountFragment) {
        regionEnd = i;
        continue;
      }

      gapRun++;
      if (gapRun > _maxGapRows) break;
    }

    if (regionStart == null || regionEnd == null) return null;
    return pageRows.sublist(regionStart, regionEnd + 1);
  }

  static bool _hasDensityRun(List<_RowShape> shapes, int startIndex) {
    var count = 0;
    for (var i = startIndex; i < shapes.length; i++) {
      if (shapes[i] != _RowShape.transactionShaped) break;
      count++;
      if (count >= _minDensityRun) return true;
    }
    return count >= _minDensityRun;
  }

  static _RowShape _classify(PdfStatementRow row, DateTime reference) {
    final text = row.text.trim();
    if (text.isEmpty) return _RowShape.other;

    final parsedDate = SmartImportDateParser.tryParse(
      text,
      referenceDate: reference,
    );
    final dateAtRowStart =
        parsedDate != null && text.indexOf(parsedDate.rawText) <= 3;
    final hasAmount = SmartImportAmountParser.extractFirst(text) != null;
    final hasTrailingDirectionCode = _trailingDirectionCodePattern.hasMatch(text);

    final isTransactionShaped =
        (dateAtRowStart && hasAmount) ||
        (dateAtRowStart && hasTrailingDirectionCode) ||
        (hasAmount && hasTrailingDirectionCode);
    if (isTransactionShaped) return _RowShape.transactionShaped;

    if (!dateAtRowStart && !hasAmount) {
      final headerWordMatches = _headerWordPattern
          .allMatches(text)
          .map((m) => m.group(0)!.toLowerCase())
          .toSet();
      if (headerWordMatches.length >= 2) return _RowShape.tableHeaderShaped;
      return _RowShape.other;
    }

    // Has a date-at-start or an amount, but not the combination (or a
    // trailing direction code) required to be fully transaction-shaped on
    // its own — most likely one row of a date-last block split across
    // several lines (see the region-scan loop for how this is used).
    return _RowShape.dateOrAmountFragment;
  }
}

enum _RowShape { transactionShaped, tableHeaderShaped, dateOrAmountFragment, other }
