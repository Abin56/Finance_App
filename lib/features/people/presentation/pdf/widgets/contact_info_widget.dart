import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/pdf/font_manager.dart';
import '../../../../../core/pdf/pdf_tokens.dart';
import '../statement_pdf_model.dart';

/// Person name, phone, email — each row omitted entirely if null/blank
/// rather than shown as an empty value, same graceful-degrade principle as
/// [StatementPdfRow.paidBy].
class ContactInfoWidget extends pw.StatelessWidget {
  ContactInfoWidget({required this.model, required this.fonts});

  final StatementPdfModel model;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          model.personName,
          style: pw.TextStyle(font: fonts.bold, fontSize: PdfTokens.fontHeading, color: PdfTokens.textPrimary),
        ),
        pw.SizedBox(height: PdfTokens.xs),
        pw.Wrap(
          spacing: PdfTokens.lg,
          runSpacing: 2,
          children: [
            _detail(model.personPhone),
            _detail(model.personEmail),
            _detail('Person since ${model.personSince.fullDate}'),
          ].whereType<pw.Widget>().toList(),
        ),
      ],
    );
  }

  pw.Widget? _detail(String? text) {
    if (text == null || text.isEmpty) return null;
    return pw.Text(
      text,
      style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontCaption, color: PdfTokens.textSecondary),
    );
  }
}
