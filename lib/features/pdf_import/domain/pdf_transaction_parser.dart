import '../../../core/utils/id_generator.dart';
import '../../smart_import/domain/detected_transaction.dart';
import '../../smart_import/domain/smart_import_amount_parser.dart';
import '../../smart_import/domain/smart_import_date_parser.dart';
import '../../smart_import/domain/smart_import_direction_detector.dart';
import '../../transactions/domain/transaction_type.dart';
import 'pdf_extraction_result.dart';
import 'pdf_layout_reconstructor.dart';
import 'pdf_transaction_region_detector.dart';

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

  // A rate, never a transaction amount — "18.00%" is structurally
  // unambiguous regardless of wording (IGST, GST, any other percentage-based
  // fee), so a candidate immediately followed by '%' is excluded from
  // amount candidacy outright, the same way an explicit balance-context
  // prefix already excludes a candidate today.
  static final RegExp _percentSuffixPattern = RegExp(r'^\s*%');

  // A bare 1-2 letter direction code (or DR/CR) directly after a candidate
  // figure is the same generic structural signal
  // `PdfTransactionRegionDetector` already uses to recognize a
  // transaction-shaped row — reused here (not duplicated as new vocabulary)
  // to prefer a candidate genuinely marked as a transaction figure over an
  // earlier, unmarked number that merely occurs first in the text.
  static final RegExp _directionCodeSuffixPattern = RegExp(
    r'^\s*\)?\s*[A-Za-z]{1,2}\b',
  );

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
    final allRows = reconstructor.reconstructRows(extraction);
    // Row-granularity region detection excludes header/account-summary
    // content before the transaction table and trailing legal/T&C content
    // after it (same page or different pages) before blocks are ever
    // formed — see `PdfTransactionRegionDetector`. Falls back to every row,
    // unfiltered, when no region can be confidently identified anywhere in
    // the document, so headerless/date-last/receipt-style layouts are
    // never reduced to zero transactions by this stage.
    final rows =
        PdfTransactionRegionDetector.detect(allRows, referenceDate: reference) ??
        allRows;
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
  /// Two additional signals, both added after a real statement reproduction
  /// proved rows could otherwise be lost or merged (see
  /// `pdf_date_block_grouping_risk` in project memory):
  ///
  /// - A date-shaped match that does not sit at the very start of the row
  ///   text is treated as prose containing a coincidental date-like
  ///   substring (e.g. "card valid thru 12 Nov offer applied"), not a real
  ///   transaction-start date, and does **not** force a split — it still
  ///   attaches as a continuation row. A genuine date-first or date-last
  ///   statement row always has its date anchored at (or essentially at)
  ///   the start of the row's own text — this is true regardless of
  ///   whether the row also carries an amount, so unlike gating on "has an
  ///   amount", it still correctly force-splits a legitimate date-first row
  ///   that turns out to have no amount anywhere (an intentionally
  ///   needs-review case covered by existing fixtures).
  /// - A row carrying an amount while the currently-open block already has
  ///   both a date and an amount is evidence a new transaction has started
  ///   even though this row has no date of its own — the common case for a
  ///   date-last layout where a new transaction's description/amount rows
  ///   arrive before its trailing date. Without this, such a row would
  ///   silently attach to the previous (already-complete) block as if it
  ///   were a continuation, and the real trailing date that follows would
  ///   never re-open a fresh block for it (a same-block date doesn't
  ///   re-trigger once `currentBlockHasDate` is already true).
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
    var currentBlockHasAmount = false;
    for (final row in rows) {
      final text = row.text.trim();
      if (text.isEmpty) continue;
      final parsedDate = SmartImportDateParser.tryParse(
        text,
        referenceDate: reference,
      );
      final looksLikeDate = parsedDate != null;
      final looksLikeAmount = SmartImportAmountParser.extractFirst(text) != null;
      final isTrustedDateRow = _isTrustedDateRow(text, parsedDate);
      final amountStartsNewBlock =
          !looksLikeDate &&
          looksLikeAmount &&
          currentBlockHasDate &&
          currentBlockHasAmount;

      // Mirror of `amountStartsNewBlock` for the opposite case: a trusted
      // date-first row that *also* carries its own amount is a
      // self-sufficient transaction start on its own — it should never be
      // swallowed by a currently-open block that already has an amount but
      // no date (e.g. a dateless fee/charge row that itself opened its own
      // block via `amountStartsNewBlock`, such as "IGST DB @ 18.00% 76.71
      // D" immediately followed by a real dated transaction). Gated on
      // `looksLikeAmount` on *this* row (not just `isTrustedDateRow`) so a
      // date-last block's own bare trailing date line — which never
      // carries an amount itself — is never mistaken for a new,
      // unrelated transaction and still correctly completes the block
      // that's waiting for it.
      final dateRowClosesAmountOnlyBlock =
          isTrustedDateRow &&
          looksLikeAmount &&
          currentBlockHasAmount &&
          !currentBlockHasDate;

      final shouldStartNewBlock =
          blocks.isEmpty ||
          (isTrustedDateRow && currentBlockHasDate) ||
          amountStartsNewBlock ||
          dateRowClosesAmountOnlyBlock;

      if (shouldStartNewBlock) {
        blocks.add(PdfStatementBlock());
        currentBlockHasDate = false;
        currentBlockHasAmount = false;
      }
      blocks.last.rows.add(row);
      if (isTrustedDateRow) currentBlockHasDate = true;
      if (looksLikeAmount) currentBlockHasAmount = true;
    }
    return blocks;
  }

  /// A date match is only trusted — for block-splitting *or* for picking a
  /// block's transaction date — when it sits at/near the start of the row's
  /// own text (a small leading-character allowance covers a stray bullet or
  /// index number before the date). A date-shaped substring buried well
  /// inside a longer sentence (e.g. a footnote reading "...transactions
  /// dated 17-Nov-2011.") is coincidental prose, not a transaction-start
  /// date, and must never be trusted as either signal — using two different
  /// trust levels for the same parser in these two call sites is what let a
  /// buried date still surface as a fabricated transaction's date even after
  /// block-splitting correctly ignored it (see `pdf_date_block_grouping_risk`
  /// in project memory).
  static bool _isTrustedDateRow(String text, ParsedDate? parsedDate) {
    if (parsedDate == null) return false;
    return text.indexOf(parsedDate.rawText) <= 3;
  }

  static DetectedTransaction? _toDetectedTransaction(
    PdfStatementBlock block,
    DateTime reference,
  ) {
    ParsedDate? parsedDate;
    String? dateRawText;
    for (final row in block.rows) {
      final text = row.text.trim();
      final parsed = SmartImportDateParser.tryParse(
        text,
        referenceDate: reference,
      );
      if (_isTrustedDateRow(text, parsed)) {
        parsedDate = parsed;
        dateRawText = parsed!.rawText;
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
    // A percentage figure ("18.00%") is never a transaction amount
    // regardless of wording (IGST, GST, any other rate) — masked out before
    // anything else runs so it's structurally invisible to every candidate
    // downstream, the same treatment a balance-context prefix already gets.
    final combinedText = _maskPercentageFigures(block.combinedText);

    // Every amount-shaped figure in the block, found once up front (rather
    // than only via the `direct`/multi-candidate fallback split below) so a
    // trailing-direction-code preference can be applied consistently
    // whenever more than one non-balance candidate exists — a bare number
    // occurring earlier in reading order (a reference ID fragment, a rate,
    // an unrelated figure) must not automatically win over a later figure
    // that's actually marked as the transaction amount by a trailing D/C/M/
    // DR/CR code, the same structural signal already used to recognize a
    // transaction-shaped row in `PdfTransactionRegionDetector`.
    final allFigures = _extractAllAmountFigures(combinedText);
    final nonBalanceFigures = allFigures.where((f) => !f.isBalanceOnly).toList();
    if (nonBalanceFigures.length > 1) {
      final directionMarked = nonBalanceFigures
          .where((f) => _hasTrailingDirectionCode(combinedText, f))
          .toList();
      if (directionMarked.isNotEmpty && directionMarked.length < nonBalanceFigures.length) {
        final chosen = directionMarked.first;
        return _AmountResult(value: chosen.value, rawText: chosen.rawText, uncertain: false);
      }
    }

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
    final figures = allFigures;
    final nonBalance = nonBalanceFigures;
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

  /// Blanks out every percentage figure ("18.00%", "18 %") in [text] in
  /// place — same length, so every other match's raw text and position stay
  /// valid for the rest of the pipeline (description-stripping,
  /// `rawText`-based masking) — leaving a rate's own digits permanently
  /// invisible to every downstream amount candidate, rather than only to
  /// the single first-choice check `extractFirst` already had.
  static String _maskPercentageFigures(String text) {
    var result = text;
    for (final match in RegExp(
      r'[0-9oOiIlLsS]+(?:[,.][0-9oOiIlLsS]+)*',
    ).allMatches(text)) {
      final afterMatch = text.substring(match.end);
      if (_percentSuffixPattern.hasMatch(afterMatch)) {
        result = result.replaceRange(
          match.start,
          match.end,
          ' ' * (match.end - match.start),
        );
      }
    }
    return result;
  }

  /// Whether [figure] (a candidate found in [text]) is immediately followed
  /// by a bare direction code — the same structural signal
  /// `PdfTransactionRegionDetector` uses to recognize a transaction-shaped
  /// row, reused here to prefer a candidate actually marked as the
  /// transaction figure over an earlier, unmarked number.
  static bool _hasTrailingDirectionCode(String text, ParsedAmount figure) {
    final idx = text.indexOf(figure.rawText);
    if (idx == -1) return false;
    final afterMatch = text.substring(idx + figure.rawText.length);
    return _directionCodeSuffixPattern.hasMatch(afterMatch);
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
