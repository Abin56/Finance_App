import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/pdf/font_manager.dart';
import '../../../../../core/pdf/pdf_tokens.dart';
import '../statement_pdf_model.dart';

/// Renders [Person.notes] verbatim when non-blank. The caller only includes
/// this section when `model.personNotesText.isNotEmpty` — there is no empty
/// "Notes" card rendered when there's nothing to say.
class NotesWidget extends pw.StatelessWidget {
  NotesWidget({required this.model, required this.fonts});

  final StatementPdfModel model;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(PdfTokens.lg),
      decoration: pw.BoxDecoration(
        color: PdfTokens.surfaceVariant,
        borderRadius: pw.BorderRadius.circular(PdfTokens.radiusLg),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Notes',
            style: pw.TextStyle(font: fonts.semiBold, fontSize: PdfTokens.fontHeading, color: PdfTokens.textPrimary),
          ),
          pw.SizedBox(height: PdfTokens.xs),
          pw.Text(
            model.personNotesText,
            style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontBody, color: PdfTokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
