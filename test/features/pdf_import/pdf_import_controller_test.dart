import 'dart:io';

import 'package:finance_app/features/pdf_import/data/services/pdf_file_picker_service.dart';
import 'package:finance_app/features/pdf_import/data/services/pdf_statement_service.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_open_outcome.dart';
import 'package:finance_app/features/pdf_import/presentation/providers/pdf_import_providers.dart';
import 'package:finance_app/features/pdf_import/presentation/providers/pdf_import_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePdfFilePickerService implements PdfFilePickerService {
  _FakePdfFilePickerService(this.outcome);
  final PdfPickOutcome outcome;

  @override
  Future<PdfPickOutcome> pickPdf() async => outcome;
}

class _FakePdfStatementService implements PdfStatementService {
  _FakePdfStatementService({
    required this.openResult,
    this.correctPassword,
    required this.successResult,
  });

  /// What plain `open()` (no password) returns.
  final PdfOpenOutcome openResult;
  final String? correctPassword;
  final PdfExtractionResult successResult;

  final List<String> passwordAttempts = [];

  @override
  Future<PdfOpenOutcome> open(File file) async => openResult;

  @override
  Future<PdfOpenOutcome> openWithPassword(File file, String password) async {
    passwordAttempts.add(password);
    if (password == correctPassword) {
      return PdfOpenOutcome.success(successResult);
    }
    return const PdfOpenOutcome.incorrectPassword();
  }
}

const _sampleResult = PdfExtractionResult(
  pages: [
    PdfPageResult(
      pageNumber: 1,
      lines: [
        PdfTextLine(
          text: 'Statement text',
          boundingBox: PdfBoundingBox(left: 0, top: 0, right: 10, bottom: 10),
          source: PdfTextSource.embedded,
        ),
      ],
      source: PdfTextSource.embedded,
    ),
  ],
);

ProviderContainer _buildContainer({
  required PdfPickOutcome pickOutcome,
  required PdfOpenOutcome openOutcome,
  String? correctPassword,
}) {
  return ProviderContainer(
    overrides: [
      pdfFilePickerServiceProvider.overrideWithValue(
        _FakePdfFilePickerService(pickOutcome),
      ),
      pdfStatementServiceProvider.overrideWithValue(
        _FakePdfStatementService(
          openResult: openOutcome,
          correctPassword: correctPassword,
          successResult: _sampleResult,
        ),
      ),
    ],
  );
}

void main() {
  group('unprotected PDF', () {
    test('pickFile() goes straight to extracted on success', () async {
      final file = File('unused.pdf');
      final container = _buildContainer(
        pickOutcome: PdfPickOutcome.success(file),
        openOutcome: PdfOpenOutcome.success(_sampleResult),
      );
      addTearDown(container.dispose);

      final picked = await container
          .read(pdfImportControllerProvider.notifier)
          .pickFile();

      expect(picked, isTrue);
      final state = container.read(pdfImportControllerProvider);
      expect(state.stage, PdfImportStage.extracted);
      expect(state.result, _sampleResult);
      expect(state.isPasswordProtected, isFalse);
    });

    test(
      'pickFile() returns false and leaves state alone when cancelled',
      () async {
        final container = _buildContainer(
          pickOutcome: const PdfPickOutcome.cancelled(),
          openOutcome: PdfOpenOutcome.success(_sampleResult),
        );
        addTearDown(container.dispose);

        final picked = await container
            .read(pdfImportControllerProvider.notifier)
            .pickFile();

        expect(picked, isFalse);
        expect(
          container.read(pdfImportControllerProvider).stage,
          PdfImportStage.pickingFile,
        );
      },
    );
  });

  group('password-protected PDF', () {
    test('moves to awaitingPassword when the PDF requires one', () async {
      final container = _buildContainer(
        pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
        openOutcome: const PdfOpenOutcome.passwordRequired(),
        correctPassword: 'sesame',
      );
      addTearDown(container.dispose);

      await container.read(pdfImportControllerProvider.notifier).pickFile();

      final state = container.read(pdfImportControllerProvider);
      expect(state.stage, PdfImportStage.awaitingPassword);
      expect(state.isPasswordProtected, isTrue);
      expect(state.passwordError, isNull);
    });

    test('correct password moves to extracted', () async {
      final container = _buildContainer(
        pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
        openOutcome: const PdfOpenOutcome.passwordRequired(),
        correctPassword: 'sesame',
      );
      addTearDown(container.dispose);
      final controller = container.read(pdfImportControllerProvider.notifier);

      await controller.pickFile();
      await controller.submitPassword('sesame');

      final state = container.read(pdfImportControllerProvider);
      expect(state.stage, PdfImportStage.extracted);
      expect(state.result, _sampleResult);
    });

    test(
      'wrong password stays on awaitingPassword with an error and allows retry',
      () async {
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
          openOutcome: const PdfOpenOutcome.passwordRequired(),
          correctPassword: 'sesame',
        );
        addTearDown(container.dispose);
        final controller = container.read(pdfImportControllerProvider.notifier);

        await controller.pickFile();
        await controller.submitPassword('wrong-guess');

        var state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.awaitingPassword);
        expect(state.passwordError, isNotNull);
        expect(state.passwordError, isNot(contains('wrong-guess')));

        // Retry with the correct password succeeds.
        await controller.submitPassword('sesame');
        state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.extracted);
      },
    );

    test('does not crash across repeated wrong password attempts', () async {
      final container = _buildContainer(
        pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
        openOutcome: const PdfOpenOutcome.passwordRequired(),
        correctPassword: 'sesame',
      );
      addTearDown(container.dispose);
      final controller = container.read(pdfImportControllerProvider.notifier);

      await controller.pickFile();
      for (final guess in ['a', 'b', 'c']) {
        await controller.submitPassword(guess);
        expect(
          container.read(pdfImportControllerProvider).stage,
          PdfImportStage.awaitingPassword,
        );
      }
    });
  });

  group('invalid/empty PDFs', () {
    test(
      'invalidPdf surfaces a plain-language error and returns to pickingFile',
      () async {
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
          openOutcome: const PdfOpenOutcome.invalidPdf(),
        );
        addTearDown(container.dispose);

        await container.read(pdfImportControllerProvider.notifier).pickFile();

        final state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.pickingFile);
        expect(state.errorMessage, 'Unable to read this PDF.');
      },
    );

    test(
      'empty PDF surfaces a plain-language "no transactions" error',
      () async {
        final container = _buildContainer(
          pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
          openOutcome: const PdfOpenOutcome.empty(),
        );
        addTearDown(container.dispose);

        await container.read(pdfImportControllerProvider.notifier).pickFile();

        final state = container.read(pdfImportControllerProvider);
        expect(state.stage, PdfImportStage.pickingFile);
        expect(state.errorMessage, contains("couldn't find any transactions"));
      },
    );
  });

  test('reset() returns to the initial state', () async {
    final container = _buildContainer(
      pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
      openOutcome: PdfOpenOutcome.success(_sampleResult),
    );
    addTearDown(container.dispose);
    final controller = container.read(pdfImportControllerProvider.notifier);

    await controller.pickFile();
    expect(
      container.read(pdfImportControllerProvider).stage,
      PdfImportStage.extracted,
    );

    controller.reset();
    expect(
      container.read(pdfImportControllerProvider).stage,
      PdfImportStage.pickingFile,
    );
    expect(container.read(pdfImportControllerProvider).result, isNull);
  });
}
