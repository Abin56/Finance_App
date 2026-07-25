import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/pdf/font_manager.dart';
import '../../../../../core/pdf/pdf_tokens.dart';
import '../../../../../core/utils/currency_formatter.dart';
import '../statement_pdf_model.dart';

/// Split/assigned-expense settlement figures — Total Spent, Total Settled,
/// Pending — with a progress bar. Scoped to Expense participations only,
/// mirroring [PersonExpenseStats]'s own doc comment; a caption makes that
/// scope explicit so a reader doesn't mistake it for a grand total covering
/// plain lending as well. The caller only renders this section when
/// `model.expenseStatsTotalSpent > 0`.
class SettlementSummaryWidget extends pw.StatelessWidget {
  SettlementSummaryWidget({required this.model, required this.fonts});

  final StatementPdfModel model;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    final fmt = CurrencyFormatter.instance;
    final progress = model.expenseStatsTotalSpent == 0
        ? 0.0
        : (model.expenseStatsTotalSettled / model.expenseStatsTotalSpent).clamp(0.0, 1.0);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(PdfTokens.lg),
      decoration: pw.BoxDecoration(
        color: PdfTokens.surface,
        borderRadius: pw.BorderRadius.circular(PdfTokens.radiusLg),
        border: pw.Border.all(color: PdfTokens.outline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Settlement Summary',
            style: pw.TextStyle(font: fonts.semiBold, fontSize: PdfTokens.fontHeading, color: PdfTokens.textPrimary),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Covers shared/assigned expenses only — not plain lending.',
            style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontCaption, color: PdfTokens.textSecondary),
          ),
          pw.SizedBox(height: PdfTokens.md),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _stat('Total Spent', fmt.format(model.expenseStatsTotalSpent)),
              _stat('Total Settled', fmt.format(model.expenseStatsTotalSettled)),
              _stat('Pending', fmt.format(model.expenseStatsPending)),
            ],
          ),
          pw.SizedBox(height: PdfTokens.md),
          pw.LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            valueColor: PdfTokens.success,
            backgroundColor: PdfTokens.outline,
          ),
        ],
      ),
    );
  }

  pw.Widget _stat(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontCaption, color: PdfTokens.textSecondary)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(font: fonts.bold, fontSize: PdfTokens.fontBody, color: PdfTokens.textPrimary)),
      ],
    );
  }
}
