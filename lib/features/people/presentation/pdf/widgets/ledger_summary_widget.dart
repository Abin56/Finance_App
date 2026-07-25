import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/pdf/font_manager.dart';
import '../../../../../core/pdf/pdf_tokens.dart';
import '../../../../../core/pdf/widgets/pdf_kpi_card.dart';
import '../../../../../core/utils/currency_formatter.dart';
import '../statement_pdf_model.dart';

/// The statement's headline KPI row — Amount Left, Total Paid Back, You
/// Lent, You Borrowed — mirroring the same four figures
/// `PersonStatementHeader` already shows on screen, so the PDF summary is
/// recognizably "the same numbers" a reader has already seen in-app.
class LedgerSummaryWidget extends pw.StatelessWidget {
  LedgerSummaryWidget({required this.model, required this.fonts});

  final StatementPdfModel model;
  final PdfFonts fonts;

  @override
  pw.Widget build(pw.Context context) {
    final fmt = CurrencyFormatter.instance;
    final balanceColor = model.isCreditor
        ? PdfTokens.success
        : model.isDebtor
            ? PdfTokens.error
            : PdfTokens.textPrimary;
    final balanceSubtitle = model.isCreditor ? 'owes you' : model.isDebtor ? 'you owe' : 'all settled';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: PdfKpiCard(
            title: 'Amount Left',
            value: fmt.format(model.currentBalance.abs()),
            subtitle: balanceSubtitle,
            valueColor: balanceColor,
            fonts: fonts,
          ),
        ),
        pw.SizedBox(width: PdfTokens.sm),
        pw.Expanded(
          child: PdfKpiCard(
            title: 'Total Paid Back',
            value: fmt.format(model.totalSettled),
            fonts: fonts,
          ),
        ),
        pw.SizedBox(width: PdfTokens.sm),
        pw.Expanded(
          child: PdfKpiCard(
            title: 'You Lent',
            value: fmt.format(model.youLent),
            fonts: fonts,
          ),
        ),
        pw.SizedBox(width: PdfTokens.sm),
        pw.Expanded(
          child: PdfKpiCard(
            title: 'You Borrowed',
            value: fmt.format(model.youBorrowed),
            fonts: fonts,
          ),
        ),
      ],
    );
  }
}
