/// A line's position on the source image, in the same pixel space the OCR
/// engine reported it in. Used to reconstruct visual transaction rows from
/// text that a vendor's line/block segmentation may have split oddly (e.g. a
/// merchant name and its amount coming back as two separate lines at the
/// same height because they sit in different UI columns).
class OcrBoundingBox {
  const OcrBoundingBox({
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
}

/// One line of recognized text plus where it sits on the image.
/// [confidence] is null for OCR engines (like on-device ML Kit) that don't
/// expose a per-line confidence score.
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  final String text;
  final OcrBoundingBox boundingBox;
  final double? confidence;
}

/// The full result of running OCR on one image. [lines] is what the
/// transaction extractor works from; [fullText] is kept for diagnostics and
/// for the "no text detected at all" empty-image error case.
class OcrResult {
  const OcrResult({required this.fullText, required this.lines});

  final String fullText;
  final List<OcrTextLine> lines;

  bool get hasText => fullText.trim().isNotEmpty;
}
