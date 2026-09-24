import '../../sms_inbox/domain/merchant/merchant_category_suggester.dart';
import '../../transactions/domain/transaction_type.dart';

/// Whether a detected row is confident enough to import as-is. Deliberately
/// binary and non-technical — the review screen shows this as "Ready" or
/// "Needs review", never a raw OCR/parser confidence score.
enum DetectionReviewStatus { ready, needsReview }

/// One transaction row extracted from a screenshot, staged for the user to
/// review, edit, and select before anything is written to Firestore.
///
/// This is intentionally a separate, lightweight class rather than a partial
/// `Transaction` — a detected row can have missing/uncertain fields
/// (`date`, `amount`, `type` all nullable) that a real `Transaction` is never
/// allowed to have, and it carries review-only state (`isSelected`,
/// duplicate flags) that has no place on the persisted domain model. Only
/// once a row is confirmed and imported does it become a real `Transaction`
/// via `TransactionRepository.createTransaction`.
///
/// Fields are mutable, matching the plain-class style of `Transaction`/
/// `Account` — the review screen edits a row in place and re-emits the list
/// to notify Riverpod listeners, rather than reconstructing immutable copies.
class DetectedTransaction {
  DetectedTransaction({
    required this.id,
    required this.sourceImageIndex,
    required this.rawText,
    this.date,
    this.hasExplicitYear = true,
    String? rawDescription,
    this.amount,
    this.type,
    this.referenceNumber,
    this.categoryId,
    this.categorySuggestionSource,
    this.isDuplicate = false,
    this.duplicateTransactionId,
    this.duplicateReason,
    this.isSelected = true,
  }) : rawDescription = rawDescription?.trim();

  /// Locally-generated id (see `IdGenerator`) — never a Firestore document
  /// id, since this row may never be imported at all.
  final String id;

  /// Index into the batch of images this row was extracted from — lets the
  /// review screen group/attribute rows back to a source screenshot when
  /// multiple images are scanned together.
  final int sourceImageIndex;

  /// The raw OCR text block this row was built from, kept only for
  /// diagnostics/debugging a bad extraction — never shown to the user and
  /// never logged (screenshots may contain sensitive account details).
  final String rawText;

  DateTime? date;

  /// False when [date]'s year had to be inferred rather than read directly
  /// off the screenshot — surfaced so a caller can be more conservative
  /// about trusting it, though it doesn't by itself force review.
  bool hasExplicitYear;

  /// Null/blank means no merchant/description text was confidently
  /// extracted — [description] then falls back to "Unknown" for display,
  /// while [hasRequiredFields] still correctly reports this row as
  /// incomplete.
  String? rawDescription;

  double? amount;
  TransactionType? type;
  String? referenceNumber;

  String? categoryId;

  /// Why [categoryId] was suggested (user history / known merchant / SMS-
  /// style type mapping) — reuses `MerchantCategorySuggester`'s enum so the
  /// review UI can explain a category suggestion the same way SMS Inbox
  /// does, instead of growing a second explanation concept.
  SuggestionSource? categorySuggestionSource;

  bool isDuplicate;
  String? duplicateTransactionId;

  /// User-facing explanation of why this looked like a duplicate, e.g.
  /// "Similar transaction already exists on 5 Sep for ₹420".
  String? duplicateReason;

  /// Set when the user explicitly chose "Import anyway" on a flagged
  /// duplicate — lets it be imported despite [isDuplicate] staying true
  /// (so the badge keeps showing), and survives a duplicate re-check as
  /// long as it keeps matching the same transaction.
  bool duplicateAcknowledged = false;

  /// Whether this row is checked for import on the review screen. Defaults
  /// to true for a ready row; the controller unchecks it on detection when
  /// the row needs review or looks like a duplicate, so the user has to
  /// affirmatively opt back in rather than accidentally import something
  /// uncertain.
  bool isSelected;

  /// Set once this row has been successfully written as a real `Transaction`
  /// — excluded from every subsequent import attempt in the same session so
  /// retrying a partially-failed import can never create it twice.
  bool isImported = false;

  String get description => (rawDescription == null || rawDescription!.isEmpty)
      ? 'Unknown'
      : rawDescription!;

  /// Matches the spec's own required-field set (date, description, amount)
  /// — [type] is deliberately excluded: it's optional/inferred (see
  /// `SmartImportDirectionDetector`), defaulting to expense when the
  /// screenshot has no explicit debit/credit wording, exactly like a manual
  /// entry does. Gating readiness on it would mark the overwhelming majority
  /// of real screenshots (which rarely spell out "DEBIT" on every row) as
  /// needing review for no good reason.
  bool get hasRequiredFields =>
      date != null &&
      amount != null &&
      amount! > 0 &&
      rawDescription != null &&
      rawDescription!.isNotEmpty;

  DetectionReviewStatus get reviewStatus => hasRequiredFields
      ? DetectionReviewStatus.ready
      : DetectionReviewStatus.needsReview;

  /// A short, plain-language reason for [DetectionReviewStatus.needsReview]
  /// — e.g. "Missing date, amount" — so the review screen can tell the user
  /// what to fix instead of leaving "Needs review" as a dead end. Null for a
  /// ready row.
  String? get missingFieldsSummary {
    final missing = <String>[
      if (date == null) 'date',
      if (amount == null || amount! <= 0) 'amount',
      if (rawDescription == null || rawDescription!.isEmpty) 'description',
    ];
    if (missing.isEmpty) return null;
    return 'Missing ${missing.join(', ')}';
  }
}
