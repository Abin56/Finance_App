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
import 'package:finance_app/features/smart_import/domain/camera_capture_outcome.dart';
import 'package:finance_app/features/smart_import/domain/ocr_result.dart';
import 'package:finance_app/features/smart_import/presentation/providers/smart_import_providers.dart';
import 'package:finance_app/features/smart_import/presentation/providers/smart_import_state.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Always returns the same canned OCR result regardless of which file it's
/// given — Smart Import's controller has no branch on image source, so
/// feeding it a "camera" file exercises the exact same
/// `ScreenshotTransactionExtractor`/`ScreenshotDuplicateDetector`/
/// `TransactionRepository` this fake stands in front of that a gallery
/// screenshot would.
class _FakeOcrService implements TransactionOcrService {
  @override
  Future<OcrResult> extractText(File image) async {
    final lines = [
      OcrTextLine(
        text: '05 Sep',
        boundingBox: const OcrBoundingBox(
          left: 0,
          top: 0,
          right: 100,
          bottom: 20,
        ),
      ),
      OcrTextLine(
        text: 'SWIGGY',
        boundingBox: const OcrBoundingBox(
          left: 0,
          top: 24,
          right: 100,
          bottom: 44,
        ),
      ),
      OcrTextLine(
        text: '₹420',
        boundingBox: const OcrBoundingBox(
          left: 0,
          top: 48,
          right: 100,
          bottom: 68,
        ),
      ),
    ];
    return OcrResult(
      fullText: lines.map((l) => l.text).join('\n'),
      lines: lines,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a camera-captured image goes through the exact same OCR → extraction → '
      'review → duplicate-check → import pipeline as a gallery screenshot — '
      'no second pipeline exists for the camera source', () async {
    SmsInboxDatabase.debugReset();
    final merchantMemoryDb = await SmsInboxDatabase.openInMemoryForTest();

    final firestore = FakeFirebaseFirestore();
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUserIdProvider.overrideWithValue('test-uid'),
        transactionOcrServiceProvider.overrideWithValue(_FakeOcrService()),
        // `SmartImportController.import()` records a merchant-category
        // memory after a successful save — the exact same after-the-fact
        // learning `completeSmsImport` uses — which needs SMS Inbox's
        // local sqflite store rather than Firestore. An in-memory test
        // database keeps this test from touching a real file.
        smsInboxDatabaseProvider.overrideWithValue(merchantMemoryDb),
      ],
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

    // `import()` reads `accountsStreamProvider` synchronously (`.value`)
    // to guard against a since-deleted account — a `StreamProvider` is
    // lazy, so without warming it here that first read would see no
    // value yet and treat the account as missing.
    await container.read(accountsStreamProvider.future);

    final controller = container.read(smartImportControllerProvider.notifier);

    // Step 1: camera capture is confirmed — indistinguishable from a
    // gallery pick from this point on (same `images` list, same File type).
    final cameraFile = File('camera_capture_test.jpg');
    controller.confirmCapturedImage(cameraFile);
    expect(container.read(smartImportControllerProvider).images, [cameraFile]);

    // Step 2: the existing OCR/extraction pipeline runs unmodified.
    await controller.processImages();
    final afterProcessing = container.read(smartImportControllerProvider);
    expect(afterProcessing.stage, SmartImportStage.reviewing);
    expect(afterProcessing.detected, hasLength(1));
    expect(afterProcessing.detected.single.description, 'Swiggy');
    expect(afterProcessing.detected.single.amount, 420.0);
    expect(
      afterProcessing.images,
      isEmpty,
      reason:
          'the camera file is cleaned up by the same mechanism a screenshot file is',
    );

    final detectedId = afterProcessing.detected.single.id;
    controller.updateTransaction(detectedId, categoryId: category.id);
    controller.setAccount(account.id);

    // Step 3: the existing import path — the same `TransactionRepository`
    // used by manual entry and SMS import — creates a real transaction.
    await controller.import();
    final afterImport = container.read(smartImportControllerProvider);
    expect(afterImport.stage, SmartImportStage.done);
    expect(afterImport.importResult?.imported, 1);

    final repository = container.read(transactionRepositoryProvider);
    final saved = await repository.getAll();
    expect(saved, hasLength(1));
    expect(saved.single.amount, 420.0);
    expect(
      saved.single.source,
      'screenshot',
      reason:
          'camera and gallery images are the same input source as far as '
          'the transaction record is concerned — no separate "camera" '
          'source tag exists, since that would mean a second code path',
    );
  });

  test(
    'captureFromCamera reports a distinct outcome for each failure mode',
    () {
      // Pure sanity check on the outcome type itself — the actual
      // image_picker/permission_handler platform-channel calls inside
      // `SmartImportController.captureFromCamera()` can't run in a plain VM
      // test without a device, so that method is exercised manually instead
      // (see the manual test checklist). This just locks down that each
      // named constructor produces the status/file pairing callers switch on.
      expect(
        const CameraCaptureOutcome.cancelled().status,
        CameraCaptureStatus.cancelled,
      );
      expect(
        const CameraCaptureOutcome.permissionDenied().status,
        CameraCaptureStatus.permissionDenied,
      );
      expect(
        const CameraCaptureOutcome.permissionPermanentlyDenied().status,
        CameraCaptureStatus.permissionPermanentlyDenied,
      );
      expect(
        const CameraCaptureOutcome.unavailable().status,
        CameraCaptureStatus.unavailable,
      );
      final file = File('x.jpg');
      final success = CameraCaptureOutcome.success(file);
      expect(success.status, CameraCaptureStatus.success);
      expect(success.file, file);
    },
  );
}
