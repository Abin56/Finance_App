import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/pdf/font_manager.dart';
import '../../../../core/pdf/pdf_tokens.dart';
import '../../../../core/pdf/widgets/pdf_footer.dart';
import '../../../../core/pdf/widgets/pdf_header_banner.dart';
import 'statement_pdf_model.dart';
import 'widgets/contact_info_widget.dart';
import 'widgets/ledger_summary_widget.dart';
import 'widgets/notes_widget.dart';
import 'widgets/settlement_summary_widget.dart';
import 'widgets/statement_info_widget.dart';
import 'widgets/transaction_table_widget.dart';

/// Assembles the final [pw.Document] for a person statement — landscape A4,
/// real `pw.Text` throughout (never a screenshotted image, unlike the
/// existing expense-receipt PDF), with a repeating table header and
/// auto-flowing pagination via [pw.MultiPage].
abstract class StatementPdfBuilder {
  StatementPdfBuilder._();

  static Future<pw.Document> build(StatementPdfModel model) async {
    final fonts = await FontManager.load();

    final doc = pw.Document(title: 'Statement for ${model.personName}', producer: 'FlowFi');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        maxPages: 200,
        header: (context) {
          if (context.pageNumber != 1) return pw.SizedBox();
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: PdfTokens.lg),
            child: PdfHeaderBanner(
              title: 'Expense Settlement Statement',
              subtitle: 'Statement for ${model.personName}',
              fonts: fonts,
            ),
          );
        },
        footer: (context) => PdfFooter(pageNumber: context.pageNumber, pagesCount: context.pagesCount, fonts: fonts),
        // `build:` is called exactly once up front with a page-less base
        // Context (`pw.MultiPage` assigns real pages to the flattened list
        // afterward as it flows content) — `context.pageNumber` is not
        // meaningful here and throws if read. The page-1-only content below
        // doesn't need a page-number check: it's simply first in the flat
        // list, so it naturally renders at the top of page 1 as MultiPage
        // flows everything in order.
        build: (context) => [
          ContactInfoWidget(model: model, fonts: fonts),
          pw.SizedBox(height: PdfTokens.lg),
          StatementInfoWidget(model: model, fonts: fonts),
          pw.SizedBox(height: PdfTokens.xl),
          LedgerSummaryWidget(model: model, fonts: fonts),
          pw.SizedBox(height: PdfTokens.xl),
          TransactionTableWidget(model: model, fonts: fonts),
          if (model.expenseStatsTotalSpent > 0) ...[
            pw.SizedBox(height: PdfTokens.xl),
            SettlementSummaryWidget(model: model, fonts: fonts),
          ],
          if (model.personNotesText.isNotEmpty) ...[
            pw.SizedBox(height: PdfTokens.lg),
            NotesWidget(model: model, fonts: fonts),
          ],
        ],
      ),
    );

    return doc;
  }
}
