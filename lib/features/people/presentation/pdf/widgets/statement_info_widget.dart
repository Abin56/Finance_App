import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/pdf/font_manager.dart';
import '../../../../../core/pdf/pdf_tokens.dart';
import '../statement_pdf_model.dart';

/// Generated-on timestamp and, when the export was made from a filtered
/// screen view, a "Showing: …" line — so a reader never mistakes a filtered
/// export for the person's full history.
class StatementInfoWidget extends pw.StatelessWidget {
  StatementInfoWidget({required this.model, required this.fonts});

  final StatementPdfModel model;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    final generated = 'Generated ${model.generatedAt.fullDate}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          generated,
          style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontCaption, color: PdfTokens.textSecondary),
        ),
        if (model.filterDescription.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'Showing: ${model.filterDescription}',
            style: pw.TextStyle(font: fonts.semiBold, fontSize: PdfTokens.fontCaption, color: PdfTokens.primary),
          ),
        ],
      ],
    );
  }
}
