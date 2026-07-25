import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../font_manager.dart';
import '../pdf_tokens.dart';

/// A small colored rounded-rect label — the PDF-safe replacement for the
/// emoji status dots (🟢🟠🔴⚪) used in the plain-text share, since Noto
/// Sans's text-only weights don't guarantee color-emoji glyph coverage.
class PdfStatusTone {
  const PdfStatusTone._(this.color);

  final PdfColor color;

  static const success = PdfStatusTone._(PdfTokens.success);
  static const warning = PdfStatusTone._(PdfTokens.warning);
  static const error = PdfStatusTone._(PdfTokens.error);
  static const neutral = PdfStatusTone._(PdfTokens.neutral);
}

class PdfStatusPill extends pw.StatelessWidget {
  PdfStatusPill({required this.label, required this.tone, required this.fonts});

  final String label;
  final PdfStatusTone tone;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: PdfTokens.sm, vertical: 3),
      decoration: pw.BoxDecoration(
        color: tone.color.withAlpha(0.12),
        borderRadius: pw.BorderRadius.circular(PdfTokens.radiusPill),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(font: fonts.semiBold, fontSize: PdfTokens.fontCaption, color: tone.color),
      ),
    );
  }
}
