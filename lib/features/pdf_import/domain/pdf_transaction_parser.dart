import '../../../core/utils/id_generator.dart';
import '../../smart_import/domain/detected_transaction.dart';
import '../../smart_import/domain/smart_import_amount_parser.dart';
import '../../smart_import/domain/smart_import_date_parser.dart';
import '../../smart_import/domain/smart_import_direction_detector.dart';
import '../../transactions/domain/transaction_type.dart';
import 'pdf_extraction_result.dart';
import 'pdf_layout_reconstructor.dart';

/// Turns a [PdfExtractionResult] into [DetectedTransaction]s: Phase 2's
/// "Universal Transaction Parser" stage.
///
/// Reuses [PdfLayoutReconstructor] to get cleaned, boilerplate-free rows,
/// then groups rows into per-transaction blocks and reuses the exact same
/// bank-agnostic field parsers Smart Import and Paste Import already rely
/// on ([SmartImportDateParser], [SmartImportAmountParser],
/// [SmartImportDirectionDetector]) — so a date, an amount, and a debit/
/// credit signal mean the same thing across every import path.
///
/// Deliberately does not assume a single statement layout: it never matches
/// on a specific bank's column header text. It only uses structural signals
/// that hold across (most) tabular bank statements — see the class-level
/// docs on [PdfLayoutReconstructor] and [_groupIntoBlocks] for the exact
/// rules, and the "known limitations" notes on [extract] for where this
/// still falls short of a true table-aware parser.
abstract class PdfTransactionParser {
  PdfTransactionParser._();

  static final RegExp _referencePattern = RegExp(
    r'(?:upi\s*)?(?:ref(?:erence)?|txn|transaction|chq|cheque)\.?\s*(?:id|no\.?|number)?[:\s]*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );

  // A bare "DR"/"CR" suffix directly after an amount — extremely common in
  // tabular statements ("1,250.00 DR", "500.00Cr") where the direction is
  // encoded next to the figure itself rather than as a separate keyword
  // elsewhere in the row. `SmartImportDirectionDetector` already recognizes
  // bare "dr"/"cr" tokens, so this pattern exists only to strip the suffix
  // out of the description text, not to detect direction itself.
  static final RegExp _amountSuffixDrCrPattern = RegExp(
    r'\b(dr|cr)\b\.?',
    caseSensitive: false,
  );

  static final RegExp _directionKeywordPattern = RegExp(
    r'\b(dr|cr|debit(?:ed)?|credit(?:ed)?|paid|payment|spent|purchase(?:d)?|sent|withdrawn|withdrawal|received|refund(?:ed)?|cashback|deposit(?:ed)?)\b',
    caseSensitive: false,
  );

  static final RegExp _punctuationNoisePattern = RegExp(r'[|:•·\-–—]+');
  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _edgePunctuationPattern = RegExp(r'^[.,\s]+|[.,\s]+$');

  // Rows that are pure table furniture — never a transaction on their own,
  // even though a header row can carry words like "Date"/"Amount" that
  // would otherwise look transaction-adjacent. Only consulted for a block
  // that has no amount at all (see `_toDetectedTransaction`), so it can
  // never cause a real transaction with incidental matching text to be
  // dropped.
  static final RegExp _nonTransactionTextPattern = RegExp(
    r'\b(statement\s+(?:of\s+account|period|date)|account\s+summary|'
    r'opening\s+balance|closing\s+balance|brought\s+forward|carried\s+forward|'
    r'page\s+\d+\s+of\s+\d+|generated\s+on|printed\s+on|'
    r'date\s+(?:description|particulars|narration)|'
    r'(?:^|\s)(?:sr\.?\s*no\.?|s\.?\s*no\.?)(?:\s|$))',
    caseSensitive: false,
  );

  /// [referenceDate] anchors year inference for dates with no explicit
  /// year — defaults to now.
  static List<DetectedTransaction> extract(
    PdfExtractionResult extraction, {
    DateTime? referenceDate,
  }) {
    if (!extraction.hasAnyText) return const [];
    final reference = referenceDate ?? DateTime.now();

    const reconstructor = PdfLayoutReconstructor();
    final rows = reconstructor.reconstructRows(extraction);
    final blocks = _groupIntoBlocks(rows, reference);

    return blocks
        .map((block) => _toDetectedTransaction(block, reference))
        .whereType<DetectedTransaction>()
        .toList();
  }

  /// A row containing a parseable date starts a new transaction block —
  /// unless the block currently open doesn't have a date yet, in which case
  /// the date attaches to that block instead. That second case is what
  /// makes a layout where the date sits at the *end* of a transaction block
  /// (some statements print date last, after description and amount) work
  /// the same as the far more common date-first layout: the date-bearing
  /// row only forces a new block when the currently-open block would
  /// otherwise end up with two dates.
  ///
  /// A continuation row with no date and no amount (a wrapped second line
  /// of a long merchant description) always attaches to whichever block is
  /// currently open, which is how multi-line descriptions are supported
  /// without any special-casing.
  ///
  /// Rows before the first date- or amount-bearing row (statement letterhead,
  /// account holder details, column headers not caught by boilerplate
  /// detection) form a leading block with neither, which
  /// [_toDetectedTransaction] then drops.
  static List<PdfStatementBlock> _groupIntoBlocks(
    List<PdfStatementRow> rows,
    DateTime reference,
  ) {
    final blocks = <PdfStatementBlock>[];
    var currentBlockHasDate = false;
    for (final row in rows) {
      final text = row.text.trim();
      if (text.isEmpty) continue;
      final looksLikeDate =
          SmartImportDateParser.tryParse(text, referenceDate: reference) !=
          null;
      if (blocks.isEmpty || (looksLikeDate && currentBlockHasDate)) {
        blocks.add(PdfStatementBlock());
        currentBlockHasDate = false;
      }
      blocks.last.rows.add(row);
      if (looksLikeDate) currentBlockHasDate = true;
    }
    return blocks;
  }

  static DetectedTransaction? _toDetectedTransaction(
    PdfStatementBlock block,
    DateTime reference,
  ) {
    ParsedDate? parsedDate;
    String? dateRawText;
    for (final row in block.rows) {
      final parsed = SmartImportDateParser.tryParse(
        row.text,
        referenceDate: reference,
      );
      if (parsed != null) {
        parsedDate = parsed;
        dateRawText = parsed.rawText;
        break;
      }
    }

    final combinedText = block.combinedText;
    final amountResult = _extractTransactionAmount(block);

    // Nothing transaction-shaped in this block — most likely a statement
    // header, account summary, or a boilerplate row that repeat-detection
    // missed (e.g. it only appeared on one page).
    if (parsedDate == null && amountResult == null) return null;
    if (amountResult == null &&
        _nonTransactionTextPattern.hasMatch(combinedText)) {
      return null;
    }

    final direction = SmartImportDirectionDetector.detect(combinedText);
    final referenceNumber = _referencePattern
        .firstMatch(combinedText)
        ?.group(1);

    final description = _extractDescription(
      block.rows,
      dateRawText: dateRawText,
      amountRawText: amountResult?.rawText,
      balanceRawText: amountResult?.balanceRawText,
    );

    final row = DetectedTransaction(
      id: IdGenerator.generate(),
      // PDF import has no concept of a source image — the block's starting
      // page number is the closest analogue, letting a future UI still
      // group/attribute rows back to a page the way screenshot import
      // groups rows back to a source image.
      sourceImageIndex: block.rows.isEmpty ? 0 : block.rows.first.pageNumber,
      rawText: combinedText,
      date: parsedDate?.date,
      hasExplicitYear: parsedDate?.hasExplicitYear ?? true,
      rawDescription: description,
      amount: amountResult?.value,
      // No explicit debit/credit wording is common for statements that
      // encode direction only via separate debit/credit columns this
      // line-based reconstruction can't always distinguish — default to
      // expense (same starting point a manual entry gets), rather than
      // leaving direction unresolved. See "known limitations".
      type: direction ?? TransactionType.expense,
      referenceNumber: referenceNumber,
    );
    // A row missing a required field, or one with an ambiguous running
    // balance figure, must never start pre-checked for import — see
    // `DetectedTransaction.isSelected`'s doc comment for why.
    row.isSelected = row.hasRequiredFields && !(amountResult?.uncertain ?? false);
    return row;
  }

  /// Picks the transaction amount out of a block, distinguishing it from a
  /// running-balance column when both are present on the same row(s).
  ///
  /// Tabular statements commonly show 2-3 amount-shaped figures on one row:
  /// a debit amount, a credit amount (one of the two usually blank/absent),
  /// and a running balance — conventionally the *last* amount-shaped figure
  /// column-wise. This uses [SmartImportAmountParser] (which already
  /// deprioritizes/flags balance-adjacent wording like "Bal"/"Balance") as
  /// the first pass, then applies a PDF-specific fallback: when a row has
  /// two or more amount-shaped figures and the parser didn't find explicit
  /// balance wording to disambiguate, the last figure (right-most column,
  /// conventionally the balance in Date/Description/Debit/Credit/Balance
  /// layouts) is treated as the running balance and excluded, leaving the
  /// first remaining figure as the transaction amount. This is a heuristic,
  /// not a guarantee — see "known limitations" on [extract].
  static _AmountResult? _extractTransactionAmount(PdfStatementBlock block) {
    final combinedText = block.combinedText;
    final direct = SmartImportAmountParser.extractFirst(combinedText);
    if (direct != null && !direct.isBalanceOnly) {
      return _AmountResult(
        value: direct.value,
        rawText: direct.rawText,
        uncertain: false,
      );
    }

    // Either nothing found, or the *first* candidate `extractFirst` prefers
    // looked balance-adjacent — that alone doesn't mean every amount-shaped
    // figure on the row is a balance. Re-scan the block with each found
    // match masked out in turn (rather than only consuming forward from
    // it), so an earlier non-balance figure — e.g. "SWIGGY 420.00 Closing
    // Balance: Rs. 12,500.00", where the currency-marked balance would
    // otherwise always win priority over the bare transaction amount ahead
    // of it — still gets found.
    final figures = _extractAllAmountFigures(combinedText);
    final nonBalance = figures.where((f) => !f.isBalanceOnly).toList();
    if (nonBalance.isNotEmpty) {
      // A genuine, non-balance-adjacent figure was found once balance-only
      // matches were masked out — trust it outright, same confidence as the
      // direct `extractFirst` case above.
      final chosen = nonBalance.first;
      final balance = figures.firstWhere(
        (f) => f.isBalanceOnly,
        orElse: () => chosen,
      );
      return _AmountResult(
        value: chosen.value,
        rawText: chosen.rawText,
        uncertain: false,
        balanceRawText: identical(balance, chosen) ? null : balance.rawText,
      );
    }

    if (figures.isEmpty) return null;

    if (figures.length == 1) {
      // A lone figure that `SmartImportAmountParser` flagged as
      // balance-only is still surfaced (flagged uncertain) rather than
      // dropped, matching Screenshot/Paste Import's own "never silently
      // drop, always let the user see and correct it" stance.
      return _AmountResult(
        value: figures.first.value,
        rawText: figures.first.rawText,
        uncertain: true,
        balanceRawText: null,
      );
    }

    // 2+ figures, all balance-adjacent: last is presumed the running
    // balance (right-most column in a Debit/Credit/Balance layout), first
    // of the rest is the transaction amount. Flagged uncertain since this
    // is a positional guess, not a confirmed column match — surfaces the
    // row for user review instead of silently trusting the guess.
    final balance = figures.last;
    final amount = figures.first;
    return _AmountResult(
      value: amount.value,
      rawText: amount.rawText,
      uncertain: true,
      balanceRawText: balance.rawText,
    );
  }

  /// Finds every amount-shaped figure in [text] by repeatedly masking out
  /// whichever match `SmartImportAmountParser.extractFirst` returns first
  /// (blanking it in place rather than only slicing the text forward from
  /// it) so an earlier, lower-priority figure — a bare decimal sitting
  /// before a later currency-marked balance — is still found on the next
  /// pass instead of being permanently shadowed by the higher-priority match
  /// ahead of it.
  static List<ParsedAmount> _extractAllAmountFigures(String text) {
    final figures = <ParsedAmount>[];
    var remaining = text;
    while (true) {
      final found = SmartImportAmountParser.extractFirst(remaining);
      if (found == null) break;
      figures.add(found);
      final idx = remaining.indexOf(found.rawText);
      if (idx == -1) break;
      remaining = remaining.replaceRange(
        idx,
        idx + found.rawText.length,
        ' ' * found.rawText.length,
      );
    }
    return figures;
  }

  static String _extractDescription(
    List<PdfStatementRow> rows, {
    required String? dateRawText,
    required String? amountRawText,
    required String? balanceRawText,
  }) {
    final parts = <String>[];
    for (final row in rows) {
      var remainder = row.text;
      if (dateRawText != null) {
        remainder = remainder.replaceAll(dateRawText, '');
      }
      if (amountRawText != null) {
        remainder = remainder.replaceAll(amountRawText, '');
      }
      if (balanceRawText != null) {
        remainder = remainder.replaceAll(balanceRawText, '');
      }
      remainder = remainder.replaceAll(_amountSuffixDrCrPattern, '');
      remainder = remainder.replaceAll(_directionKeywordPattern, '');
      remainder = _cleanFragment(remainder);
      if (remainder.isNotEmpty) parts.add(remainder);
    }
    return _cleanFragment(parts.join(' '));
  }

  static String _cleanFragment(String text) {
    var cleaned = text
        .replaceAll(_punctuationNoisePattern, ' ')
        .replaceAll(_whitespacePattern, ' ')
        .trim();
    cleaned = cleaned.replaceAll(_edgePunctuationPattern, '').trim();
    return cleaned;
  }
}

class _AmountResult {
  const _AmountResult({
    required this.value,
    required this.rawText,
    required this.uncertain,
    this.balanceRawText,
  });

  final double value;
  final String rawText;

  /// True when the amount was picked via a positional heuristic (last
  /// figure = balance, first-of-rest = amount) rather than confirmed by an
  /// explicit currency marker or balance-wording exclusion — the caller
  /// uses this to avoid pre-selecting the row for import.
  final bool uncertain;
  final String? balanceRawText;
}
