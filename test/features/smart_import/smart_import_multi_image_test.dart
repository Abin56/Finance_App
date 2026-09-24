@TestOn('vm')
library;

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/smart_import/data/services/transaction_ocr_service.dart';
import 'package:finance_app/features/smart_import/domain/ocr_result.dart';
import 'package:finance_app/features/smart_import/presentation/providers/smart_import_providers.dart';
import 'package:finance_app/features/smart_import/presentation/providers/smart_import_state.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

OcrTextLine _ocrLine(String text, double top) {
  return OcrTextLine(
    text: text,
    boundingBox: OcrBoundingBox(left: 0, top: top, right: 150, bottom: top + 20),
  );
}

/// Returns a different canned OCR result per file path (keyed by the file's
/// basename), or throws for a path registered as "failing" — lets a single
/// test simulate a realistic multi-screenshot batch where each image
/// contains different transactions, and/or one image is unreadable, without
/// depending on ML Kit or any real image content.
class _KeyedFakeOcrService implements TransactionOcrService {
  _KeyedFakeOcrService(this.resultsByPath, {this.failingPaths = const {}});

  final Map<String, OcrResult> resultsByPath;
  final Set<String> failingPaths;

  final List<String> callOrder = [];

  @override
  Future<OcrResult> extractText(File image) async {
    callOrder.add(image.path);
    if (failingPaths.contains(image.path)) {
      throw Exception('simulated OCR failure for ${image.path}');
    }
    return resultsByPath[image.path] ??
        const OcrResult(fullText: '', lines: []);
  }
}

OcrResult _resultFor(String date, String merchant, String amount) {
  final lines = [
    _ocrLine(date, 0),
    _ocrLine(merchant, 24),
    _ocrLine(amount, 48),
  ];
  return OcrResult(fullText: lines.map((l) => l.text).join('\n'), lines: lines);
}

ProviderContainer _buildContainer({
  required TransactionOcrService ocrService,
  required SmsInboxDatabase merchantMemoryDb,
  required FakeFirebaseFirestore firestore,
}) {
  return ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUserIdProvider.overrideWithValue('test-uid'),
      transactionOcrServiceProvider.overrideWithValue(ocrService),
      smsInboxDatabaseProvider.overrideWithValue(merchantMemoryDb),
    ],
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase merchantMemoryDb;
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    merchantMemoryDb = await SmsInboxDatabase.openInMemoryForTest();
    firestore = FakeFirebaseFirestore();
  });

  group('SmartImportController — multi-image selection and processing', () {
    test('a single image still works exactly as before (no regression)', () async {
      final ocrService = _KeyedFakeOcrService({
        'shot1.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
      });
      final container = _buildContainer(
        ocrService: ocrService,
        merchantMemoryDb: merchantMemoryDb,
        firestore: firestore,
      );
      addTearDown(container.dispose);
      await container.read(accountsStreamProvider.future);

      final controller = container.read(smartImportControllerProvider.notifier);
      controller.confirmCapturedImage(File('shot1.jpg'));

      await controller.processImages();

      final state = container.read(smartImportControllerProvider);
      expect(state.stage, SmartImportStage.reviewing);
      expect(state.detected, hasLength(1));
      expect(state.detected.single.sourceImageIndex, 0);
      expect(state.detected.single.amount, 420.0);
      expect(state.errorMessage, isNull);
    });

    test(
      'multiple images are scanned sequentially and their transactions combined '
      'with correct sourceImageIndex per row',
      () async {
        final ocrService = _KeyedFakeOcrService({
          'shot1.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
          'shot2.jpg': _resultFor('06 Sep', 'UBER', '₹185.50'),
          'shot3.jpg': _resultFor('07 Sep', 'AMAZON', '₹1,299'),
        });
        final container = _buildContainer(
          ocrService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
          firestore: firestore,
        );
        addTearDown(container.dispose);
        await container.read(accountsStreamProvider.future);

        final controller = container.read(
          smartImportControllerProvider.notifier,
        );
        controller.confirmCapturedImage(File('shot1.jpg'));
        controller.confirmCapturedImage(File('shot2.jpg'));
        controller.confirmCapturedImage(File('shot3.jpg'));
        expect(
          container.read(smartImportControllerProvider).images,
          hasLength(3),
        );

        await controller.processImages();

        final state = container.read(smartImportControllerProvider);
        expect(state.stage, SmartImportStage.reviewing);
        // Processing happened in selection order — verified via the fake's
        // own call log, independent of the detected-rows assertions below.
        expect(ocrService.callOrder, ['shot1.jpg', 'shot2.jpg', 'shot3.jpg']);

        expect(state.detected, hasLength(3));
        expect(
          state.detected.map((d) => d.sourceImageIndex).toList(),
          [0, 1, 2],
          reason:
              'each row must be attributed back to the image it came from',
        );
        expect(state.detected[0].amount, 420.0);
        expect(state.detected[1].amount, 185.50);
        expect(state.detected[2].amount, 1299.0);
        expect(
          state.images,
          isEmpty,
          reason: 'scanned images are cleaned up once review begins',
        );
      },
    );

    test(
      'the same transaction appearing in two screenshots is flagged as a '
      'within-batch duplicate rather than imported twice',
      () async {
        final ocrService = _KeyedFakeOcrService({
          'shot1.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
          // Same date/merchant/amount, re-photographed or appearing again
          // in a second screenshot (e.g. a scrolling transaction list with
          // overlapping content).
          'shot2.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
        });
        final container = _buildContainer(
          ocrService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
          firestore: firestore,
        );
        addTearDown(container.dispose);
        await container.read(accountsStreamProvider.future);

        final controller = container.read(
          smartImportControllerProvider.notifier,
        );
        controller.confirmCapturedImage(File('shot1.jpg'));
        controller.confirmCapturedImage(File('shot2.jpg'));

        await controller.processImages();

        final state = container.read(smartImportControllerProvider);
        expect(state.detected, hasLength(2));
        final first = state.detected[0];
        final second = state.detected[1];
        expect(
          first.isDuplicate,
          isFalse,
          reason: 'the first occurrence is the clean original',
        );
        expect(
          second.isDuplicate,
          isTrue,
          reason: 'the second occurrence within the same batch is flagged',
        );
        expect(
          second.isSelected,
          isFalse,
          reason: 'a freshly-flagged duplicate is unchecked until overridden',
        );
      },
    );

    test(
      'one unreadable image among several does not discard the successfully '
      'processed images — the batch continues and surfaces a partial-failure note',
      () async {
        final ocrService = _KeyedFakeOcrService(
          {
            'good1.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
            'good2.jpg': _resultFor('06 Sep', 'UBER', '₹185.50'),
          },
          failingPaths: {'bad.jpg'},
        );
        final container = _buildContainer(
          ocrService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
          firestore: firestore,
        );
        addTearDown(container.dispose);
        await container.read(accountsStreamProvider.future);

        final controller = container.read(
          smartImportControllerProvider.notifier,
        );
        controller.confirmCapturedImage(File('good1.jpg'));
        controller.confirmCapturedImage(File('bad.jpg'));
        controller.confirmCapturedImage(File('good2.jpg'));

        await controller.processImages();

        final state = container.read(smartImportControllerProvider);
        expect(
          state.stage,
          SmartImportStage.reviewing,
          reason:
              'a single failed image must not abort a batch that otherwise succeeded',
        );
        expect(state.detected, hasLength(2));
        expect(state.detected[0].amount, 420.0);
        expect(state.detected[1].amount, 185.50);
        expect(
          state.errorMessage,
          contains("Couldn't read 1 of 3 images"),
          reason:
              'the user must be told one image was skipped, not left to '
              'silently wonder why they got fewer transactions than expected',
        );
      },
    );

    test(
      'every image failing OCR reports a clear error and returns to picking images',
      () async {
        final ocrService = _KeyedFakeOcrService(
          {},
          failingPaths: {'bad1.jpg', 'bad2.jpg'},
        );
        final container = _buildContainer(
          ocrService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
          firestore: firestore,
        );
        addTearDown(container.dispose);
        await container.read(accountsStreamProvider.future);

        final controller = container.read(
          smartImportControllerProvider.notifier,
        );
        controller.confirmCapturedImage(File('bad1.jpg'));
        controller.confirmCapturedImage(File('bad2.jpg'));

        await controller.processImages();

        final state = container.read(smartImportControllerProvider);
        expect(state.stage, SmartImportStage.pickingImages);
        expect(state.detected, isEmpty);
        expect(state.errorMessage, isNotNull);
        expect(
          state.errorMessage,
          isNot(contains('Exception')),
          reason: 'the underlying exception text must never reach the user',
        );
      },
    );

    test(
      'an image with no readable text among otherwise-successful images does '
      'not itself count as a failure (distinct from an OCR exception)',
      () async {
        final ocrService = _KeyedFakeOcrService({
          'good.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
          'blank.jpg': const OcrResult(fullText: '', lines: []),
        });
        final container = _buildContainer(
          ocrService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
          firestore: firestore,
        );
        addTearDown(container.dispose);
        await container.read(accountsStreamProvider.future);

        final controller = container.read(
          smartImportControllerProvider.notifier,
        );
        controller.confirmCapturedImage(File('good.jpg'));
        controller.confirmCapturedImage(File('blank.jpg'));

        await controller.processImages();

        final state = container.read(smartImportControllerProvider);
        expect(state.stage, SmartImportStage.reviewing);
        expect(state.detected, hasLength(1));
        expect(
          state.errorMessage,
          isNull,
          reason:
              'a blank/no-text image is not an OCR failure — no partial-failure note',
        );
      },
    );

    test(
      'a full end-to-end multi-image batch imports correctly through the shared repository',
      () async {
        final ocrService = _KeyedFakeOcrService({
          'shot1.jpg': _resultFor('05 Sep', 'SWIGGY', '₹420'),
          'shot2.jpg': _resultFor('06 Sep', 'UBER', '₹185.50'),
        });
        final container = _buildContainer(
          ocrService: ocrService,
          merchantMemoryDb: merchantMemoryDb,
          firestore: firestore,
        );
        addTearDown(container.dispose);

        final account = await container
            .read(accountRepositoryProvider)
            .createAccount(
              name: 'Wallet',
              type: AccountType.cash,
              openingBalance: 1000,
              colorValue: 0xFF5B5FEF,
            );
        final category = await container
            .read(categoryRepositoryProvider)
            .createCategory(
              name: 'Food',
              type: CategoryType.expense,
              iconKey: 'restaurant',
              colorValue: 0xFF00BC7D,
            );
        await container.read(accountsStreamProvider.future);

        final controller = container.read(
          smartImportControllerProvider.notifier,
        );
        controller.confirmCapturedImage(File('shot1.jpg'));
        controller.confirmCapturedImage(File('shot2.jpg'));
        await controller.processImages();

        final afterProcessing = container.read(smartImportControllerProvider);
        expect(afterProcessing.detected, hasLength(2));

        controller.selectAll();
        for (final row in afterProcessing.detected) {
          controller.updateTransaction(row.id, categoryId: category.id);
        }
        controller.setAccount(account.id);

        await controller.import();

        final afterImport = container.read(smartImportControllerProvider);
        expect(afterImport.stage, SmartImportStage.done);
        expect(afterImport.importResult?.imported, 2);
        expect(afterImport.importResult?.failed, 0);

        final saved = await container
            .read(transactionRepositoryProvider)
            .getAll();
        expect(saved, hasLength(2));
        expect(saved.every((t) => t.source == 'screenshot'), isTrue);
        expect(saved.map((t) => t.amount), containsAll([420.0, 185.50]));

        // Retrying the import must never create either transaction twice.
        await controller.retryImport();
        final savedAfterRetry = await container
            .read(transactionRepositoryProvider)
            .getAll();
        expect(savedAfterRetry, hasLength(2));
      },
    );
  });
}
