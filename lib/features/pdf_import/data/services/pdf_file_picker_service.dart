import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// What happened when the user tried to pick a PDF file. Mirrors
/// `CameraCaptureOutcome`'s status-plus-payload shape (see
/// `smart_import/domain/camera_capture_outcome.dart`) for the same reason:
/// every outcome (including "cancelled") needs its own branch, not a single
/// nullable return the caller might mistake for a failure.
enum PdfPickStatus { success, cancelled }

class PdfPickOutcome {
  const PdfPickOutcome._(this.status, this.file);

  const PdfPickOutcome.success(File file) : this._(PdfPickStatus.success, file);

  const PdfPickOutcome.cancelled() : this._(PdfPickStatus.cancelled, null);

  final PdfPickStatus status;

  /// Only non-null when [status] is [PdfPickStatus.success].
  final File? file;
}

/// Thin wrapper around `file_picker` scoped to PDF selection — `image_picker`
/// (already used by Screenshot Import) has no way to select a non-image
/// document, so this is a separate package rather than an extension of the
/// existing picker.
class PdfFilePickerService {
  const PdfFilePickerService();

  Future<PdfPickOutcome> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return const PdfPickOutcome.cancelled();
    }

    final path = result.files.single.path;
    if (path == null) return const PdfPickOutcome.cancelled();

    return PdfPickOutcome.success(File(path));
  }
}
