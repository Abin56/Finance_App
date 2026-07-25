import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/pdf/font_manager.dart';
import '../../../../../core/pdf/pdf_tokens.dart';
import '../../../../../core/pdf/widgets/pdf_status_pill.dart';
import '../../../../../core/utils/currency_formatter.dart';
import '../statement_pdf_model.dart';

/// The 7-column Transaction History table — Date, Description, Category,
/// Paid By, Amount, Balance, Status — built on [pw.TableHelper.fromTextArray]
/// so the header row repeats natively on every page inside a [pw.MultiPage]
/// (the `TableRow(repeat: true)` mechanism that API sets up internally),
/// while still allowing per-column widths/alignment/styling that a plain
/// string-array table wouldn't support cleanly.
///
/// "Payment Type" from the original brief is deliberately absent — no field
/// anywhere in the ledger data model indicates cash/UPI/bank/card, and a
/// column that would always read blank is worse than not having it. "Paid
/// By" is kept because [StatementPdfRow.paidBy] is honestly derivable from
/// the entry's signed-amount direction.
class TransactionTableWidget extends pw.StatelessWidget {
  TransactionTableWidget({required this.model, required this.fonts});

  final StatementPdfModel model;
  final PdfFonts fonts;

  static const _columnWidths = <int, pw.TableColumnWidth>{
    0: pw.FlexColumnWidth(1.1), // Date
    1: pw.FlexColumnWidth(3.2), // Description
    2: pw.FlexColumnWidth(1.6), // Category
    3: pw.FlexColumnWidth(1.1), // Paid By
    4: pw.FlexColumnWidth(1.3), // Amount
    5: pw.FlexColumnWidth(1.3), // Balance
    6: pw.FlexColumnWidth(1.4), // Status
  };

  @override
  pw.Widget build(pw.Context context) {
    if (model.rows.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: PdfTokens.xxl),
        alignment: pw.Alignment.center,
        child: pw.Text(
          model.filterDescription.isEmpty ? 'No transactions yet' : 'No transactions match this view',
          style: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontBody, color: PdfTokens.textSecondary),
        ),
      );
    }

    final fmt = CurrencyFormatter.instance;

    return pw.TableHelper.fromTextArray(
      headers: const ['Date', 'Description', 'Category', 'Paid By', 'Amount', 'Balance', 'Status'],
      data: [
        for (final row in model.rows)
          [
            row.date.fullDate,
            _description(row),
            row.category,
            row.paidBy,
            fmt.format(row.displayAmount.abs()),
            fmt.format(row.runningBalanceAfter),
            row.statusLabel == null
                ? ''
                : PdfStatusPill(label: row.statusLabel!, tone: row.statusTone!, fonts: fonts),
          ],
      ],
      columnWidths: _columnWidths,
      border: null,
      headerDecoration: const pw.BoxDecoration(color: PdfTokens.surfaceVariant),
      headerHeight: 28,
      headerStyle: pw.TextStyle(font: fonts.semiBold, fontSize: PdfTokens.fontBody, color: PdfTokens.textPrimary),
      headerAlignment: pw.Alignment.centerLeft,
      headerAlignments: const {
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.center,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: PdfTokens.sm, vertical: PdfTokens.sm),
      cellStyle: pw.TextStyle(font: fonts.regular, fontSize: PdfTokens.fontBody, color: PdfTokens.textPrimary),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: const {
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.center,
      },
      textStyleBuilder: (index, data, rowNum) {
        if (index == 4 || index == 5) {
          return pw.TextStyle(font: fonts.bold, fontSize: PdfTokens.fontBody, color: PdfTokens.textPrimary);
        }
        return null;
      },
      cellDecoration: (index, data, rowNum) {
        final isOdd = rowNum.isOdd;
        return pw.BoxDecoration(color: isOdd ? PdfTokens.surfaceVariant : PdfTokens.surface);
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfTokens.surfaceVariant),
    );
  }

  static String _description(StatementPdfRow row) {
    if (row.note == null || row.note!.isEmpty) return row.title;
    return row.note!;
  }
}
