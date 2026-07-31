import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../font_manager.dart';
import '../pdf_tokens.dart';

/// A small colored rounded-rect label — the PDF-safe replacement for the
/// emoji status dots (🟢🟠🔴⚪) used in the plain-text share, since Noto
/// Sans's text-only weights don't guarantee color-emoji glyph coverage.
class PdfStatusTone {
  const PdfStatusTone._(this.color, this.background);

  final PdfColor color;

  /// [color] pre-blended at 12% over [PdfTokens.surface], fully opaque.
  /// True alpha transparency (`PdfColor.withAlpha`) renders correctly in
  /// some PDF viewers but shows as solid/near-black in others (Chrome's PDF
  /// viewer, several mobile viewers, and the `printing` package's own
  /// preview have all been observed doing this) — baking the tint into an
  /// opaque color sidesteps viewer-dependent transparency compositing
  /// entirely, since [PdfTokens] colors are always painted on a white
  /// background anyway (PDFs never render in dark mode here).
  final PdfColor background;

  static const success = PdfStatusTone._(PdfTokens.success, PdfColor.fromInt(0xFFE3F8EE));
  static const warning = PdfStatusTone._(PdfTokens.warning, PdfColor.fromInt(0xFFFFF2E2));
  static const error = PdfStatusTone._(PdfTokens.error, PdfColor.fromInt(0xFFFFE7E7));
  static const neutral = PdfStatusTone._(PdfTokens.neutral, PdfColor.fromInt(0xFFE9E9EC));
}

class PdfStatusPill extends pw.StatelessWidget {
  PdfStatusPill({required this.label, required this.tone, required this.fonts});

  final String label;
  final PdfStatusTone tone;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: PdfTokens.sm - 1, vertical: 3),
      decoration: pw.BoxDecoration(
        color: tone.background,
        borderRadius: pw.BorderRadius.circular(PdfTokens.radiusPill),
        border: pw.Border.all(color: tone.color, width: 0.6),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(font: fonts.semiBold, fontSize: PdfTokens.fontCaption - 0.5, color: tone.color),
      ),
    );
  }
}
