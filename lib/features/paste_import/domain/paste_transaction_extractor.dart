import '../../../core/utils/id_generator.dart';
import '../../smart_import/domain/detected_transaction.dart';
import '../../smart_import/domain/smart_import_amount_parser.dart';
import '../../smart_import/domain/smart_import_date_parser.dart';
import '../../smart_import/domain/smart_import_direction_detector.dart';
import '../../transactions/domain/transaction_type.dart';

/// One group of pasted-text lines believed to describe a single transaction.
class _Block {
  final List<String> lines = [];
}

/// Turns freeform pasted transaction text (copied from a bank app, UPI app,
/// SMS, email, or a banking website) into [DetectedTransaction]s.
///
/// Deliberately independent of `ScreenshotTransactionExtractor` — that class
/// reconstructs rows from OCR bounding boxes, which has no meaning for plain
/// pasted text. This extractor instead relies on the two structural signals
/// pasted transaction text actually offers: blank lines separating entries
/// (a multi-line transaction per the source app's own copy formatting) and,
/// when there are none, one transaction per line. Field extraction itself
/// reuses the same generic, bank-agnostic parsers Smart Import already
/// validated (date/amount/direction), so both import paths agree on what a
/// date, an amount, and a debit/credit signal look like.
abstract class PasteTransactionExtractor {
  PasteTransactionExtractor._();

  // Broader than a bank-screenshot's usual "Ref No"/"UPI Ref" wording — real
  // Google Pay/PhonePe copy-paste text almost always says "UPI transaction
  // ID:" or "Transaction ID", neither of which the narrower phrasing below
  // matched, so pasted UPI-app receipts never got a reference number at all.
  static final RegExp _referencePattern = RegExp(
    r'(?:upi\s*)?(?:ref(?:erence)?|txn|transaction)\.?\s*(?:id|no\.?|number)?[:\s]*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );

  // Google Pay/PhonePe-style copy text wraps the merchant in a connecting
  // phrase ("Paid to Swiggy", "Received from Amit") and a timestamp line
  // ("05 Sep 2026, 10:32 PM") — left in, both survive into the description
  // and corrupt merchant-based category suggestion and history matching,
  // which key off an *exact* normalized merchant string
  // (`MerchantCategorySuggester._fromHistory`), not a fuzzy one.
  static final RegExp _upiBoilerplatePattern = RegExp(
    r'\b(?:paid\s+to|received\s+from|sent\s+to|payment\s+to|transferred\s+to|credited\s+from|debited\s+to)\b',
    caseSensitive: false,
  );

  static final RegExp _timeOfDayPattern = RegExp(
    r'\b\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm)\b',
    caseSensitive: false,
  );

  // PhonePe in particular renders the merchant on its own line prefixed with
  // a bare "To "/"From " (no "paid"/"sent" alongside it) — anchored to the
  // very start of a line so it can never eat into a merchant name that
  // legitimately contains "to"/"from" mid-string.
  static final RegExp _leadingToFromPattern = RegExp(r'^\s*(?:to|from)\s+', caseSensitive: false);

  static final RegExp _directionKeywordPattern = RegExp(
    r'\b(dr|cr|debit(?:ed)?|credit(?:ed)?|paid|payment|spent|purchase(?:d)?|sent|withdrawn|withdrawal|received|refund(?:ed)?|cashback|deposit(?:ed)?)\b',
    caseSensitive: false,
  );

  // `SmartImportAmountParser` never trusts a bare integer with no currency
  // marker or decimal tail — sound for noisy OCR, but pasted bank/UPI text
  // routinely writes amounts as a plain "420" immediately followed by "DR"/
  // "Debit" ("05 Sep SWIGGY 420 DR"), where the adjacent debit/credit word is
  // itself strong enough confirmation that the number is an amount, not a
  // date fragment. Tried only as a fallback when the shared parser finds
  // nothing on a line.
  static final RegExp _amountNearDirectionPattern = RegExp(
    r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*'
    r'(?:dr|cr|debit(?:ed)?|credit(?:ed)?|paid|payment|spent|purchase(?:d)?|sent|withdrawn|withdrawal|received|refund(?:ed)?|cashback|deposit(?:ed)?)\b',
    caseSensitive: false,
  );

  static final RegExp _blankLinePattern = RegExp(r'\n\s*\n+');
  static final RegExp _punctuationNoisePattern = RegExp(r'[|:•·\-–—]+');
  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _edgePunctuationPattern = RegExp(r'^[.,\s]+|[.,\s]+$');

  /// [referenceDate] anchors year inference for dates with no explicit year
  /// — defaults to now (today's date is the only "statement context" a
  /// pasted-text import has available).
  static List<DetectedTransaction> extract(String text, {DateTime? referenceDate}) {
    final reference = referenceDate ?? DateTime.now();
    final blocks = _splitIntoBlocks(text, reference);

    var index = 0;
    final result = <DetectedTransaction>[];
    for (final block in blocks) {
      final transaction = _toDetectedTransaction(block, index, reference);
      if (transaction != null) {
        result.add(transaction);
        index++;
      }
    }
    return result;
  }

  static List<_Block> _splitIntoBlocks(String text, DateTime reference) {
    final paragraphs = text
        .split(_blankLinePattern)
        .map((p) => p.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList())
        .where((lines) => lines.isNotEmpty)
        .toList();

    final blocks = <_Block>[];
    for (final paragraph in paragraphs) {
      if (paragraph.length == 1) {
        blocks.add(_Block()..lines.add(paragraph.first));
        continue;
      }

      // A dense paste with no blank-line separators (one transaction per
      // line) arrives as a single large paragraph — detected by every line
      // independently carrying its own date, which a genuinely multi-line
      // single transaction (date/merchant/amount split across lines) never
      // does.
      final linesWithOwnDate = paragraph
          .where((line) => SmartImportDateParser.tryParse(line, referenceDate: reference) != null)
          .length;
      final looksLikeOneTransactionPerLine =
          linesWithOwnDate == paragraph.length && paragraph.length > 1;

      if (looksLikeOneTransactionPerLine) {
        for (final line in paragraph) {
          blocks.add(_Block()..lines.add(line));
        }
      } else {
        blocks.add(_Block()..lines.addAll(paragraph));
      }
    }
    return blocks;
  }

  static DetectedTransaction? _toDetectedTransaction(
    _Block block,
    int blockIndex,
    DateTime reference,
  ) {
    ParsedDate? parsedDate;
    String? dateRawText;
    for (final line in block.lines) {
      final parsed = SmartImportDateParser.tryParse(line, referenceDate: reference);
      if (parsed != null) {
        parsedDate = parsed;
        dateRawText = parsed.rawText;
        break;
      }
    }

    ParsedAmount? parsedAmount;
    for (final line in block.lines) {
      final parsed = SmartImportAmountParser.extractFirst(line);
      if (parsed == null) continue;
      if (parsedAmount == null || (!parsedAmount.hadCurrencyMarker && parsed.hadCurrencyMarker)) {
        parsedAmount = parsed;
      }
    }

    if (parsedAmount == null) {
      for (final line in block.lines) {
        final fallback = _extractAmountNearDirection(line);
        if (fallback != null) {
          parsedAmount = fallback;
          break;
        }
      }
    }

    // Nothing transaction-shaped in this block — most likely a header,
    // balance summary, or unrelated line, not a missed transaction.
    if (parsedDate == null && parsedAmount == null) return null;

    final combinedText = block.lines.join(' ');
    final direction = SmartImportDirectionDetector.detect(combinedText);
    final referenceMatch = _referencePattern.firstMatch(combinedText);
    final referenceNumber = referenceMatch?.group(1);

    final description = _extractDescription(
      block.lines,
      dateRawText: dateRawText,
      amountRawText: parsedAmount?.rawText,
      referenceRawText: referenceMatch?.group(0),
    );

    return DetectedTransaction(
      id: IdGenerator.generate(),
      sourceImageIndex: blockIndex,
      rawText: combinedText,
      date: parsedDate?.date,
      hasExplicitYear: parsedDate?.hasExplicitYear ?? true,
      rawDescription: description,
      amount: parsedAmount?.value,
      // No explicit debit/credit wording is common for a plain
      // "merchant + amount" line — default to expense (same as a manual
      // entry starts), rather than leaving direction unresolved.
      type: direction ?? TransactionType.expense,
      referenceNumber: referenceNumber,
    );
  }

  static ParsedAmount? _extractAmountNearDirection(String line) {
    final match = _amountNearDirectionPattern.firstMatch(line);
    if (match == null) return null;
    final token = match.group(1)!.replaceAll(',', '');
    final value = double.tryParse(token);
    if (value == null || value <= 0 || value > 100000000) return null;
    return ParsedAmount(value: value, rawText: match.group(1)!, hadCurrencyMarker: false);
  }

  static String _extractDescription(
    List<String> lines, {
    required String? dateRawText,
    required String? amountRawText,
    required String? referenceRawText,
  }) {
    final parts = <String>[];
    for (final line in lines) {
      var remainder = line;
      if (dateRawText != null) remainder = remainder.replaceAll(dateRawText, '');
      if (amountRawText != null) remainder = remainder.replaceAll(amountRawText, '');
      if (referenceRawText != null) remainder = remainder.replaceAll(referenceRawText, '');
      // Must run before `_directionKeywordPattern` — "paid" alone is one of
      // that pattern's debit keywords, so stripping it first would leave a
      // dangling "to" that the multi-word "paid to" phrase below can no
      // longer match.
      remainder = remainder.replaceAll(_upiBoilerplatePattern, '');
      remainder = remainder.replaceAll(_directionKeywordPattern, '');
      remainder = remainder.replaceAll(_timeOfDayPattern, '');
      remainder = remainder.replaceFirst(_leadingToFromPattern, '');
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
    if (cleaned.isEmpty) return '';

    final isShouting = cleaned == cleaned.toUpperCase() && cleaned != cleaned.toLowerCase();
    if (!isShouting) return cleaned;

    return cleaned
        .toLowerCase()
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
