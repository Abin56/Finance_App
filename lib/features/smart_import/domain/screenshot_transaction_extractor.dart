import '../../../core/utils/id_generator.dart';
import '../../transactions/domain/transaction_type.dart';
import 'detected_transaction.dart';
import 'ocr_result.dart';
import 'smart_import_amount_parser.dart';
import 'smart_import_date_parser.dart';
import 'smart_import_direction_detector.dart';

/// One visual row reconstructed from OCR lines that sit at (roughly) the
/// same height — a bank/UPI screenshot routinely renders a date, a merchant
/// name and an amount as separate text elements placed side by side, and an
/// OCR engine reports each as its own line.
class _VisualRow {
  _VisualRow(this.text, this.top);
  final String text;
  final double top;
}

class _Block {
  final List<String> rowTexts = [];
}

/// Turns one screenshot's OCR output into a list of [DetectedTransaction]s.
///
/// Deliberately bank-agnostic: it never matches on a specific app's wording
/// or layout. Instead it uses two generic signals every transaction-shaped
/// screenshot shares — a parseable date marks where one transaction record
/// starts, and line position (via bounding boxes) reconstructs rows that a
/// vendor's own line segmentation split across columns.
class ScreenshotTransactionExtractor {
  const ScreenshotTransactionExtractor();

  static final RegExp _referencePattern = RegExp(
    r'(?:ref(?:erence)?\.?\s*(?:no\.?|number)?|txn\s*id|UPI\s*Ref(?:\s*No)?)[:\s]*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );

  static final RegExp _directionKeywordPattern = RegExp(
    r'\b(dr|cr|debit(?:ed)?|credit(?:ed)?|paid|spent|purchase(?:d)?|sent|withdrawn|withdrawal|received|refund(?:ed)?|cashback|deposit(?:ed)?)\b',
    caseSensitive: false,
  );

  // Common statement/page boilerplate that carries a date (so it would
  // otherwise survive as a needs-review row with no amount) but is never
  // itself a transaction — "Statement generated on 07 Sep 2026", "Page 2 of
  // 5", "Statement period 01 Sep - 30 Sep 2026". Only ever consulted for a
  // block that has no amount at all; a block that also has a real amount is
  // never dropped by this, however this text appears within it.
  static final RegExp _nonTransactionTextPattern = RegExp(
    r'\b(generated\s+on|statement\s+period|statement\s+date|page\s+\d+\s+of\s+\d+|printed\s+on|account\s+summary)\b',
    caseSensitive: false,
  );

  // A clock-time fragment ("8:15 PM", "10:32:05") that rides along on the
  // same visual row as a date in a wallet app's receipt/list layout
  // ("05 Sep 2026, 10:32 PM") — stripped alongside the matched date text so
  // it doesn't leak into the reconstructed description as junk like
  // "8 15 Pm".
  static final RegExp _timeOfDayPattern = RegExp(
    r'\b\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?\b',
  );

  static final RegExp _punctuationNoisePattern = RegExp(r'[|:•·\-–—]+');
  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _edgePunctuationPattern = RegExp(r'^[.,\s]+|[.,\s]+$');

  // A row that is *only* an amount ("₹350", "1,299.00") — the visual anchor
  // a UPI wallet's transaction *list* (as opposed to a single transaction-
  // detail receipt) repeats once per row: amount, then "Paid to X", then a
  // date/time line, then the next amount starts the next entry. Used by
  // [_groupIntoBlocks] the same way a date-bearing row is: a second amount-
  // only row only starts a new block when the block currently open already
  // has one, so a multi-entry list is split into one block per transaction
  // instead of every row merging into a single block.
  static final RegExp _amountOnlyRowPattern = RegExp(
    r'^\s*(?:₹|rs\.?|inr)?\s*[0-9oOiIlLsS][0-9oOiIlLsS,.]*\s*(?:/-)?\s*$',
    caseSensitive: false,
  );

  /// [referenceDate] anchors year inference for dates with no explicit year
  /// — defaults to now.
  List<DetectedTransaction> extract(
    OcrResult result, {
    required int sourceImageIndex,
    DateTime? referenceDate,
  }) {
    if (result.lines.isEmpty) return const [];
    final reference = referenceDate ?? DateTime.now();

    final rows = _buildVisualRows(result);
    final blocks = _groupIntoBlocks(rows, reference);

    return blocks
        .map(
          (block) => _toDetectedTransaction(block, sourceImageIndex, reference),
        )
        .whereType<DetectedTransaction>()
        .toList();
  }

  List<_VisualRow> _buildVisualRows(OcrResult result) {
    final lines = [...result.lines]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final heights =
        lines.map((l) => l.boundingBox.height).where((h) => h > 0).toList()
          ..sort();
    final medianHeight = heights.isEmpty ? 20.0 : heights[heights.length ~/ 2];
    final mergeThreshold = medianHeight * 0.6;

    final grouped = <List<int>>[]; // indices into `lines`
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

    return grouped.map((group) {
      final ordered = [...group]
        ..sort(
          (a, b) =>
              lines[a].boundingBox.left.compareTo(lines[b].boundingBox.left),
        );
      final text = ordered.map((idx) => lines[idx].text).join(' ').trim();
      final top = group
          .map((idx) => lines[idx].boundingBox.top)
          .reduce((a, b) => a < b ? a : b);
      return _VisualRow(text, top);
    }).toList();
  }

  /// A row containing a parseable date starts a new transaction block —
  /// unless the block currently open doesn't have one yet, in which case the
  /// date attaches to it instead. That second case matters for a single-
  /// transaction "receipt" screenshot (Google Pay/PhonePe's transaction
  /// detail view is the canonical example: big amount first, "Paid to
  /// Merchant" below it, and the date/time line *last*) — without it, that
  /// trailing date line was read as the start of a second, bogus transaction
  /// even though the block above it never got a date of its own.
  ///
  /// The same rule applies to a row that is *only* an amount: a wallet
  /// app's *list* view (as opposed to a single receipt) repeats the
  /// amount-first/merchant/date shape once per entry, so a second amount-
  /// only row starts a new block exactly when the block currently open
  /// already has one — otherwise every entry in the list would merge into
  /// one giant block and only the first amount/date would survive.
  ///
  /// Every other row attaches to whichever block is currently open. Rows
  /// that appear before the first date- or amount-bearing row (page
  /// headers, account summaries) form a leading block with no date/amount,
  /// which [_toDetectedTransaction] then drops entirely since it has
  /// neither.
  List<_Block> _groupIntoBlocks(List<_VisualRow> rows, DateTime reference) {
    final blocks = <_Block>[];
    var currentBlockHasDate = false;
    var currentBlockHasAmount = false;
    for (final row in rows) {
      final text = row.text.trim();
      if (text.isEmpty) continue;
      final looksLikeDate =
          SmartImportDateParser.tryParse(text, referenceDate: reference) !=
          null;
      final looksLikeAmountOnly =
          _amountOnlyRowPattern.hasMatch(text) &&
          SmartImportAmountParser.extractFirst(text) != null;
      if (blocks.isEmpty ||
          (looksLikeDate && currentBlockHasDate) ||
          (looksLikeAmountOnly && currentBlockHasAmount)) {
        blocks.add(_Block());
        currentBlockHasDate = false;
        currentBlockHasAmount = false;
      }
      blocks.last.rowTexts.add(text);
      if (looksLikeDate) currentBlockHasDate = true;
      if (looksLikeAmountOnly) currentBlockHasAmount = true;
    }
    return blocks;
  }

  DetectedTransaction? _toDetectedTransaction(
    _Block block,
    int sourceImageIndex,
    DateTime reference,
  ) {
    ParsedDate? parsedDate;
    String? dateRawText;
    for (final rowText in block.rowTexts) {
      final parsed = SmartImportDateParser.tryParse(
        rowText,
        referenceDate: reference,
      );
      if (parsed != null) {
        parsedDate = parsed;
        dateRawText = parsed.rawText;
        break;
      }
    }

    // Searched across the whole block (not row-by-row) so a balance figure
    // on one row can be correctly passed over in favor of the real
    // transaction amount on another row of the same block.
    final combinedText = block.rowTexts.join(' ');
    var parsedAmount = SmartImportAmountParser.extractFirst(combinedText);
    if (parsedAmount?.isBalanceOnly ?? false) {
      // Every amount-shaped figure in this block was balance wording
      // ("Avl Bal", "Closing Balance", …) — a balance is never itself a
      // transaction, so this is treated as "no amount found" rather than
      // risk silently importing a balance as a transaction amount.
      parsedAmount = null;
    }

    // Nothing transaction-shaped in this block at all — most likely a page
    // header, account summary, or statement footer, not a missed
    // transaction.
    if (parsedDate == null && parsedAmount == null) return null;
    if (parsedAmount == null &&
        _nonTransactionTextPattern.hasMatch(combinedText)) {
      return null;
    }

    final direction = SmartImportDirectionDetector.detect(combinedText);
    final referenceNumber = _referencePattern
        .firstMatch(combinedText)
        ?.group(1);

    final description = _extractDescription(
      block.rowTexts,
      dateRawText: dateRawText,
      amountRawText: parsedAmount?.rawText,
    );

    final row = DetectedTransaction(
      id: IdGenerator.generate(),
      sourceImageIndex: sourceImageIndex,
      rawText: combinedText,
      date: parsedDate?.date,
      hasExplicitYear: parsedDate?.hasExplicitYear ?? true,
      rawDescription: description,
      amount: parsedAmount?.value,
      // No explicit debit/credit wording is the common case for a plain
      // "merchant + amount" row — default to expense (same as a manual
      // entry starts), rather than leaving direction unresolved.
      type: direction ?? TransactionType.expense,
      referenceNumber: referenceNumber,
    );
    // A row missing a required field must not start pre-checked for import —
    // otherwise "Import Selected" would silently attempt (and fail) it
    // without the user ever having consciously opted in. See
    // `DetectedTransaction.isSelected`'s doc comment.
    row.isSelected = row.hasRequiredFields;
    return row;
  }

  /// Whatever text remains once the matched date/amount substrings and any
  /// bare debit/credit keyword are stripped out of each row — the closest
  /// generic proxy for "the merchant/description" without assuming any
  /// particular layout.
  String _extractDescription(
    List<String> rowTexts, {
    required String? dateRawText,
    required String? amountRawText,
  }) {
    final parts = <String>[];
    for (final rowText in rowTexts) {
      var remainder = rowText;
      if (dateRawText != null) {
        remainder = remainder.replaceAll(dateRawText, '');
      }
      if (amountRawText != null) {
        remainder = remainder.replaceAll(amountRawText, '');
      }
      remainder = remainder.replaceAll(_directionKeywordPattern, '');
      remainder = remainder.replaceAll(_timeOfDayPattern, '');
      remainder = _cleanFragment(remainder);
      if (remainder.isNotEmpty) parts.add(remainder);
    }
    return _cleanFragment(parts.join(' '));
  }

  String _cleanFragment(String text) {
    var cleaned = text
        .replaceAll(_punctuationNoisePattern, ' ')
        .replaceAll(_whitespacePattern, ' ')
        .trim();
    cleaned = cleaned.replaceAll(_edgePunctuationPattern, '').trim();
    if (cleaned.isEmpty) return '';

    final isShouting =
        cleaned == cleaned.toUpperCase() && cleaned != cleaned.toLowerCase();
    if (!isShouting) return cleaned;

    return cleaned
        .toLowerCase()
        .split(' ')
        .map(
          (word) =>
              word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }
}
