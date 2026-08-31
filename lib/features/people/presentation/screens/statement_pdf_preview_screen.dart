import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/author_name.dart';
import '../../domain/person.dart';
import '../../domain/person_timeline_entry.dart';
import '../pdf/statement_pdf_builder.dart';
import '../pdf/statement_pdf_model.dart';
import '../providers/person_expense_stats_provider.dart';

/// Full-screen preview of the generated statement PDF, opened from
/// [PersonStatementScreen]'s overflow menu ("Export PDF"). Mirrors
/// `ShareExpensePreviewScreen`'s "preview before send" pattern, using the
/// `printing` package's [PdfPreview] widget for a real scrollable/paginated
/// preview plus its own built-in share/print actions.
class StatementPdfPreviewScreen extends StatelessWidget {
  const StatementPdfPreviewScreen({super.key, required this.model});

  final StatementPdfModel model;

  static Future<void> open(
    BuildContext context, {
    required Person person,
    required List<PersonTimelineEntry> entries,
    required PersonExpenseStats expenseStats,
    required String filterDescription,
    required double openingBalanceForRange,
    required String? currentUserEmail,
    String? currentUserDisplayName,
  }) {
    final model = StatementPdfModel.build(
      person: person,
      entriesOldestFirst: entries,
      expenseStats: expenseStats,
      filterDescription: filterDescription,
      openingBalanceForRange: openingBalanceForRange,
      currentUserName: authorNameFromEmail(currentUserEmail, displayName: currentUserDisplayName),
    );
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatementPdfPreviewScreen(model: model)),
    );
  }

  String get _fileStem {
    final slug = model.personName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'flowfi_statement_${slug.isEmpty ? 'person' : slug.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statement PDF')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: PdfPreview(
            build: (format) async {
              final doc = await StatementPdfBuilder.build(model);
              return doc.save();
            },
            pdfFileName: '$_fileStem.pdf',
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }
}
