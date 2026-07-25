import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../font_manager.dart';
import '../pdf_tokens.dart';

/// A rounded stat card — title, large bold amount, optional subtitle —
/// used for the statement's Ledger Summary row. Sizing is left to the
/// parent (typically an [pw.Expanded] inside a [pw.Row]) so a variable
/// number of cards can share a row evenly.
class PdfKpiCard extends pw.StatelessWidget {
  PdfKpiCard({
    required this.title,
    required this.value,
    required this.fonts,
    this.subtitle,
    this.valueColor = PdfTokens.textPrimary,
  });

  final String title;
  final String value;
  final String? subtitle;
  final PdfFonts fonts;
  final PdfColor valueColor;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(PdfTokens.md),
      decoration: pw.BoxDecoration(
        color: PdfTokens.surfaceVariant,
        borderRadius: pw.BorderRadius.circular(PdfTokens.radiusLg),
        border: pw.Border.all(color: PdfTokens.outline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontCaption, color: PdfTokens.textSecondary),
          ),
          pw.SizedBox(height: PdfTokens.xs),
          pw.Text(
            value,
            style: pw.TextStyle(font: fonts.bold, fontSize: PdfTokens.fontHeading, color: valueColor),
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle!,
              style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontCaption, color: PdfTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
