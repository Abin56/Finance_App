import 'pdf_extraction_result.dart';

/// What happened when trying to open/decrypt and read a statement PDF.
/// Kept as an explicit outcome (mirrors `CameraCaptureOutcome` in
/// `smart_import/domain/camera_capture_outcome.dart`) rather than throwing,
/// so the UI can show the right plain-language message for each case instead
/// of parsing exception text — see the feature's error-state requirements
/// (never show a stack trace, never guess at a wrong-password vs. corrupt
/// file distinction from a generic exception).
enum PdfOpenStatus {
  /// Opened (no password, or password already supplied and correct) and at
  /// least one page was read successfully.
  success,

  /// The PDF is encrypted and no password (or an as-yet-unverified one) was
  /// supplied — caller should prompt for a password and retry.
  passwordRequired,

  /// A password was supplied but Syncfusion rejected it.
  incorrectPassword,

  /// Not a valid/parseable PDF at all (corrupt file, wrong file type despite
  /// the .pdf extension, zero-byte file, etc.).
  invalidPdf,

  /// Valid, unlocked PDF but it has zero pages or no content of any kind.
  empty,
}

class PdfOpenOutcome {
  const PdfOpenOutcome._(this.status, this.result);

  const PdfOpenOutcome.success(PdfExtractionResult result)
    : this._(PdfOpenStatus.success, result);

  const PdfOpenOutcome.passwordRequired()
    : this._(PdfOpenStatus.passwordRequired, null);

  const PdfOpenOutcome.incorrectPassword()
    : this._(PdfOpenStatus.incorrectPassword, null);

  const PdfOpenOutcome.invalidPdf() : this._(PdfOpenStatus.invalidPdf, null);

  const PdfOpenOutcome.empty() : this._(PdfOpenStatus.empty, null);

  final PdfOpenStatus status;

  /// Only non-null when [status] is [PdfOpenStatus.success].
  final PdfExtractionResult? result;
}
