import 'package:finance_app/features/sms_inbox/data/merchant_learning_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/correction_event.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learned_field.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learning_source.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_learning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the sqflite-backed persistence layer for the in-memory
/// merchant learning engine (`lib/features/sms_inbox/domain/learning/`).
/// This layer only ever persists what a caller explicitly passes in — it
/// must never invent a profile off an SMS scan, and never touch hard SMS
/// evidence (amount/direction/account/reference/status).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase db;
  late MerchantLearningDao dao;
  late MerchantLearningRepository repo;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    db = await SmsInboxDatabase.openInMemoryForTest();
    dao = MerchantLearningDao(db);
    repo = MerchantLearningRepository(dao);
  });

  tearDown(() async {
    await db.database.close();
  });

  group('profile save + reload', () {
    test('getOrCreateProfile does not create until explicitly called', () async {
      expect(await dao.getProfile('u1', 'swiggy'), isNull);
    });

    test('save then reload a category field survives a fresh DAO instance', () async {
      final now = DateTime(2026, 1, 1);
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: now,
      );

      final reloadedDao = MerchantLearningDao(db);
      final profile = await reloadedDao.getProfile('u1', 'swiggy');
      expect(profile, isNotNull);
      expect(profile!.category.value, 'food_delivery');
      expect(profile.category.source, LearningSource.user);
      expect(profile.category.corrections, 1);
      expect(profile.category.lastUpdatedAt, now);
    });

    test('merchant type, provider, and payment method round-trip', () async {
      final now = DateTime(2026, 2, 1);
      await repo.applyCorrection<MerchantType>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.merchantType,
        newValue: MerchantType.business,
        at: now,
      );
      await repo.applyCorrection<PaymentProvider>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.paymentProvider,
        newValue: PaymentProvider.phonePe,
        at: now,
      );
      await repo.applyCorrection<PaymentMethod>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.paymentMethod,
        newValue: PaymentMethod.upi,
        at: now,
      );

      final profile = await dao.getProfile('u1', 'swiggy');
      expect(profile!.merchantType.value, MerchantType.business);
      expect(profile.paymentProvider.value, PaymentProvider.phonePe);
      expect(profile.paymentMethod.value, PaymentMethod.upi);
    });
  });

  group('isolation', () {
    test('two users never see each other\'s profile for the same merchant', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: DateTime(2026, 1, 1),
      );

      expect(await dao.getProfile('u2', 'swiggy'), isNull);
      final u1Profile = await dao.getProfile('u1', 'swiggy');
      expect(u1Profile!.category.value, 'food_delivery');
    });

    test('listProfiles only returns rows for the requested user', () async {
      await dao.getOrCreateProfile('u1', 'swiggy');
      await dao.getOrCreateProfile('u1', 'zomato');
      await dao.getOrCreateProfile('u2', 'swiggy');

      final u1Profiles = await dao.listProfiles('u1');
      expect(u1Profiles.map((p) => p.merchantKey), unorderedEquals(['swiggy', 'zomato']));
    });
  });

  group('merchant key normalization / distinctness', () {
    test('Swiggy and Swiggy Instamart persist as distinct profiles', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: DateTime(2026, 1, 1),
      );
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy instamart',
        field: LearnedFieldType.category,
        newValue: 'groceries',
        at: DateTime(2026, 1, 1),
      );

      final swiggy = await dao.getProfile('u1', 'swiggy');
      final instamart = await dao.getProfile('u1', 'swiggy instamart');
      expect(swiggy!.category.value, 'food_delivery');
      expect(instamart!.category.value, 'groceries');
    });

    test('a payment provider name is rejected as a merchant key', () async {
      expect(
        () => repo.getOrCreateProfile('u1', 'phonepe'),
        throwsArgumentError,
      );
      expect(
        () => repo.applyCorrection<String>(
          userId: 'u1',
          merchantKey: 'google pay',
          field: LearnedFieldType.category,
          newValue: 'transfers',
          at: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('correction history', () {
    test('multiple corrections are all preserved in order, surviving reload', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'shopping',
        at: DateTime(2026, 1, 1),
      );
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'electronics',
        at: DateTime(2026, 1, 5),
      );

      final reloadedRepo = MerchantLearningRepository(MerchantLearningDao(db));
      final history = await reloadedRepo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(2));
      expect(history[0].oldValue, isNull);
      expect(history[0].newValue, 'shopping');
      expect(history[1].oldValue, 'shopping');
      expect(history[1].newValue, 'electronics');

      final profile = await dao.getProfile('u1', 'amazon');
      expect(profile!.category.value, 'electronics');
      expect(profile.category.corrections, 2);
    });

    test('confirmations do not add correction history rows', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'shopping',
        at: DateTime(2026, 1, 1),
      );
      await repo.confirmField<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        at: DateTime(2026, 1, 10),
      );

      final history = await repo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(1));

      final profile = await dao.getProfile('u1', 'amazon');
      expect(profile!.category.confirmations, 1);
      expect(profile.category.value, 'shopping');
    });
  });

  group('delete / clear', () {
    test('deleteProfile removes only the targeted profile', () async {
      await dao.getOrCreateProfile('u1', 'swiggy');
      await dao.getOrCreateProfile('u1', 'zomato');

      await repo.deleteProfile('u1', 'swiggy');

      expect(await dao.getProfile('u1', 'swiggy'), isNull);
      expect(await dao.getProfile('u1', 'zomato'), isNotNull);
    });

    test('clearAllForUser wipes profiles and correction history for that user only', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: DateTime(2026, 1, 1),
      );
      await repo.applyCorrection<String>(
        userId: 'u2',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: DateTime(2026, 1, 1),
      );

      await repo.clearAllForUser('u1');

      expect(await dao.listProfiles('u1'), isEmpty);
      expect(await dao.getCorrectionHistory('u1', 'swiggy'), isEmpty);
      expect(await dao.listProfiles('u2'), isNotEmpty);
    });
  });

  group('conflicting observations are never silently deleted', () {
    test('an older correction stays in history even after a newer one wins', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'shopping',
        at: DateTime(2026, 1, 1),
      );
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'electronics',
        at: DateTime(2026, 1, 5),
      );
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'shopping',
        at: DateTime(2026, 1, 10),
      );

      final history = await repo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(3));
      expect(history.map((e) => e.newValue), ['shopping', 'electronics', 'shopping']);
    });
  });

  group('atomicity', () {
    test('a failure mid-transaction leaves no partial profile or history change', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'amazon',
        field: LearnedFieldType.category,
        newValue: 'shopping',
        at: DateTime(2026, 1, 1),
      );

      Object? caught;
      try {
        await dao.transaction((txnDao) async {
          final profile = await txnDao.getOrCreateProfile('u1', 'amazon');
          await txnDao.saveProfile(
            profile.copyWith(
              category: profile.category.correctedTo(
                'electronics',
                DateTime(2026, 2, 1),
              ),
            ),
          );
          await txnDao.recordCorrection(
            'u1',
            CorrectionEvent(
              merchantKey: 'amazon',
              field: LearnedFieldType.category,
              oldValue: 'shopping',
              newValue: 'electronics',
              timestamp: DateTime(2026, 2, 1),
            ),
          );
          throw StateError('simulated failure after both writes queued');
        });
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>());

      final profile = await dao.getProfile('u1', 'amazon');
      expect(profile!.category.value, 'shopping', reason: 'profile update must have rolled back');
      final history = await dao.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(1), reason: 'correction append must have rolled back too');
    });
  });
}
