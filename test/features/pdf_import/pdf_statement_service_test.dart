import 'dart:io';
import 'dart:ui';

import 'package:finance_app/features/pdf_import/data/services/pdf_statement_service.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_open_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Builds a real, in-memory-generated PDF (via Syncfusion's own writer) with
/// [pageTexts] lines of text, one page per string, optionally encrypted with
/// [userPassword]. Using a real generated PDF rather than a hand-rolled byte
/// fixture keeps these tests honest about what `PdfDocument` can actually
/// open, at the cost of depending on Syncfusion's writer being correct —
/// acceptable since both writer and reader come from the same package.
Future<File> _buildPdf(
  Directory dir,
  String name, {
  List<String> pageTexts = const ['Statement line one'],
  String? userPassword,
}) async {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final text in pageTexts) {
    document.pages.add().graphics.drawString(
      text,
      font,
      bounds: const Rect.fromLTWH(20, 20, 500, 20),
    );
  }
  if (userPassword != null) {
    document.security.userPassword = userPassword;
  }
  final bytes = await document.save();
  document.dispose();

  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PdfStatementService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_import_test');
    service = SyncfusionPdfStatementService();
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('unprotected PDFs', () {
    test('opens a single-page text PDF and extracts its text', () async {
      final file = await _buildPdf(
        tempDir,
        'single.pdf',
        pageTexts: ['Hello statement'],
      );

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.success);
      expect(outcome.result!.pageCount, 1);
      expect(outcome.result!.fullText, contains('Hello statement'));
    });

    test('extracts and combines text across multiple pages in order', () async {
      final file = await _buildPdf(
        tempDir,
        'multi.pdf',
        pageTexts: [
          'Page one content',
          'Page two content',
          'Page three content',
        ],
      );

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.success);
      expect(outcome.result!.pageCount, 3);
      expect(outcome.result!.pages[0].pageNumber, 1);
      expect(outcome.result!.pages[1].pageNumber, 2);
      expect(outcome.result!.pages[2].pageNumber, 3);
      expect(outcome.result!.pages[0].fullText, contains('Page one'));
      expect(outcome.result!.pages[1].fullText, contains('Page two'));
      expect(outcome.result!.pages[2].fullText, contains('Page three'));
    });

    test('reports empty for a PDF with pages but no text content', () async {
      final document = PdfDocument();
      document.pages.add();
      final bytes = await document.save();
      document.dispose();
      final file = File('${tempDir.path}/blank.pdf');
      await file.writeAsBytes(bytes);

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.empty);
    });
  });

  group('password-protected PDFs', () {
    test('open() reports passwordRequired without a password', () async {
      final file = await _buildPdf(
        tempDir,
        'protected.pdf',
        pageTexts: ['Secret statement line'],
        userPassword: 'correct-horse',
      );

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.passwordRequired);
      expect(outcome.result, isNull);
    });

    test('openWithPassword() succeeds with the correct password', () async {
      final file = await _buildPdf(
        tempDir,
        'protected2.pdf',
        pageTexts: ['Secret statement line'],
        userPassword: 'correct-horse',
      );

      final outcome = await service.openWithPassword(file, 'correct-horse');

      expect(outcome.status, PdfOpenStatus.success);
      expect(outcome.result!.fullText, contains('Secret statement line'));
    });

    test(
      'openWithPassword() reports incorrectPassword for a wrong password',
      () async {
        final file = await _buildPdf(
          tempDir,
          'protected3.pdf',
          pageTexts: ['Secret statement line'],
          userPassword: 'correct-horse',
        );

        final outcome = await service.openWithPassword(file, 'wrong-guess');

        expect(outcome.status, PdfOpenStatus.incorrectPassword);
        expect(outcome.result, isNull);
      },
    );

    test('retry after a wrong password succeeds with the right one', () async {
      final file = await _buildPdf(
        tempDir,
        'protected4.pdf',
        pageTexts: ['Retry me'],
        userPassword: 'sesame',
      );

      final first = await service.openWithPassword(file, 'nope');
      expect(first.status, PdfOpenStatus.incorrectPassword);

      final second = await service.openWithPassword(file, 'sesame');
      expect(second.status, PdfOpenStatus.success);
      expect(second.result!.fullText, contains('Retry me'));
    });

    test(
      'does not crash and does not leak the password on repeated wrong attempts',
      () async {
        final file = await _buildPdf(
          tempDir,
          'protected5.pdf',
          pageTexts: ['Line'],
          userPassword: 'correct',
        );

        for (final guess in ['a', 'b', 'c']) {
          final outcome = await service.openWithPassword(file, guess);
          expect(outcome.status, PdfOpenStatus.incorrectPassword);
        }
      },
    );
  });

  group('invalid input', () {
    test('reports invalidPdf for a non-PDF file', () async {
      final file = File('${tempDir.path}/not_a_pdf.pdf');
      await file.writeAsString('this is definitely not a pdf file');

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.invalidPdf);
    });

    test('reports invalidPdf for an empty file', () async {
      final file = File('${tempDir.path}/empty.pdf');
      await file.writeAsBytes(const []);

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.invalidPdf);
    });

    test('reports invalidPdf for a missing file without throwing', () async {
      final file = File('${tempDir.path}/does_not_exist.pdf');

      final outcome = await service.open(file);

      expect(outcome.status, PdfOpenStatus.invalidPdf);
    });
  });
}
