// Manual diagnostic harness — NOT part of the regular test suite in intent.
// Runs the real production pipeline (SyncfusionPdfStatementService ->
// PdfLayoutReconstructor -> PdfTransactionParser) against a real bank
// statement PDF path supplied via the PDF_ANALYSIS_PATH environment
// variable, and prints extracted raw text plus detected transactions for
// manual comparison against the PDF's visible content. No parser code is
// touched by this file; it only calls the existing public APIs.
//
// Run with:
//   flutter test test/features/pdf_import/_real_pdf_analysis_harness_test.dart --dart-define=PDF_ANALYSIS_PATH="<path>"
// or set the PDF_ANALYSIS_PATH environment variable before running.
import 'dart:io';

import 'package:finance_app/features/pdf_import/data/services/pdf_statement_service.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_layout_reconstructor.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_open_outcome.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _pathFromDefine = String.fromEnvironment('PDF_ANALYSIS_PATH');

void main() {
  test('real PDF analysis harness', () async {
    final path = _pathFromDefine.isNotEmpty
        ? _pathFromDefine
        : Platform.environment['PDF_ANALYSIS_PATH'] ?? '';
    if (path.isEmpty) {
      // ignore: avoid_print
      print('SKIPPED: no PDF_ANALYSIS_PATH provided.');
      return;
    }

    final file = File(path);
    if (!file.existsSync()) {
      // ignore: avoid_print
      print('FILE NOT FOUND: $path');
      return;
    }

    final service = SyncfusionPdfStatementService();
    var outcome = await service.open(file);

    if (outcome.status == PdfOpenStatus.passwordRequired) {
      final password = Platform.environment['PDF_ANALYSIS_PASSWORD'];
      if (password == null || password.isEmpty) {
        // ignore: avoid_print
        print('PASSWORD REQUIRED: set PDF_ANALYSIS_PASSWORD env var.');
        return;
      }
      outcome = await service.openWithPassword(file, password);
    }

    // ignore: avoid_print
    print('=== OPEN STATUS: ${outcome.status} ===');
    if (outcome.status != PdfOpenStatus.success || outcome.result == null) {
      return;
    }

    final extraction = outcome.result!;
    // ignore: avoid_print
    print('=== PAGE COUNT: ${extraction.pageCount} ===');
    // ignore: avoid_print
    print('=== looksLikeScannedDocument: ${extraction.looksLikeScannedDocument} ===');

    // ignore: avoid_print
    print('\n=== RAW EXTRACTED TEXT (per page) ===');
    for (final page in extraction.pages) {
      // ignore: avoid_print
      print('--- page ${page.pageNumber} (${page.lines.length} lines) ---');
      for (final line in page.lines) {
        // ignore: avoid_print
        print(
          '  top=${line.boundingBox.top.toStringAsFixed(1)} '
          'left=${line.boundingBox.left.toStringAsFixed(1)} '
          'text="${line.text}"',
        );
      }
    }

    const reconstructor = PdfLayoutReconstructor();
    final rows = reconstructor.reconstructRows(extraction);
    // ignore: avoid_print
    print('\n=== RECONSTRUCTED ROWS (after boilerplate strip + row grouping): ${rows.length} ===');
    for (final row in rows) {
      // ignore: avoid_print
      print('  page=${row.pageNumber} top=${row.top.toStringAsFixed(1)} text="${row.text}"');
    }

    final detected = PdfTransactionParser.extract(extraction, referenceDate: DateTime.now());
    // ignore: avoid_print
    print('\n=== DETECTED TRANSACTIONS: ${detected.length} ===');
    for (var i = 0; i < detected.length; i++) {
      final t = detected[i];
      // ignore: avoid_print
      print(
        '[$i] date=${t.date} amount=${t.amount} type=${t.type} '
        'selected=${t.isSelected} reviewStatus=${t.reviewStatus} '
        'sourcePage=${t.sourceImageIndex} desc="${t.description}"',
      );
    }
  });
}
