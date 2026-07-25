import 'package:pdf/widgets.dart' as pw;

import '../font_manager.dart';
import '../pdf_tokens.dart';

/// The branded band at the top of page 1 — wordmark, document title, and
/// subtitle. No emoji (Noto Sans's text weights don't guarantee color-emoji
/// glyph coverage) — brand identity comes from the primary-color fill and
/// wordmark alone, same intent as `ShareFormat.header`'s 💸 banner without
/// the glyph risk.
class PdfHeaderBanner extends pw.StatelessWidget {
  PdfHeaderBanner({required this.title, required this.subtitle, required this.fonts});

  final String title;
  final String subtitle;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: PdfTokens.xl, vertical: PdfTokens.lg),
      decoration: pw.BoxDecoration(
        color: PdfTokens.primary,
        borderRadius: pw.BorderRadius.circular(PdfTokens.radiusLg),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(font: fonts.bold, fontSize: PdfTokens.fontTitle, color: PdfTokens.surface),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                subtitle,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: PdfTokens.fontBody,
                  color: PdfTokens.surface,
                ),
              ),
            ],
          ),
          pw.Text(
            'FLOWFI',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: PdfTokens.fontHeading,
              color: PdfTokens.surface,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
