import 'package:finance_app/features/sms_inbox/data/merchant_learning_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/financial_event_learning_service.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learned_field.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learning_source.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_learning_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/user_learning_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises `FinancialEventLearningService` — the capture layer that turns
/// an explicit user confirm/correct action into calls against
/// `MerchantLearningRepository`. This layer never runs on its own; every
/// test here calls it directly, exactly like a future UI would after a user
/// tap. It must never touch hard SMS evidence (amount/direction/account/
/// status/reference) — `UserLearningAction` has no such fields at all, so
/// no test can even attempt to pass them; see the "structural exclusion"
/// group below for how that's demonstrated.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase db;
  late MerchantLearningRepository repo;
  late FinancialEventLearningService service;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    db = await SmsInboxDatabase.openInMemoryForTest();
    repo = MerchantLearningRepository(MerchantLearningDao(db));
    service = FinancialEventLearningService(repo);
  });

  tearDown(() async {
    await db.database.close();
  });

  group('confirmation', () {
    // A confirmation reaffirms a value that already exists on the profile
    // (e.g. an AI/inference suggestion) — it never invents one, matching
    // `LearnedField.confirmedAt`'s semantics of leaving `value` untouched.
    // So "first confirmation" here means the first *user* confirmation of an
    // already-suggested value.
    test('first user confirmation of a suggested value increments confirmations', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: DateTime(2025, 12, 1),
        source: LearningSource.ai,
      );

      final result = await service.confirmFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy', category: 'food_delivery'),
        at: DateTime(2026, 1, 1),
      );

      expect(result.merchantKey, 'swiggy');
      expect(result.confirmedFields, [LearnedFieldType.category]);
      expect(result.confirmationsRecorded, 1);
      expect(result.correctionsRecorded, 0);
      expect(result.explanation, contains('Confirmed'));

      final profile = await repo.getProfile('u1', 'swiggy');
      expect(profile!.category.value, 'food_delivery');
      expect(profile.category.confirmations, 1);
      expect(profile.category.corrections, 1, reason: 'the AI-sourced write still counts as the sole correction');
    });

    test('repeated confirmation increments confirmations without any correction event', () async {
      await repo.applyCorrection<String>(
        userId: 'u1',
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        newValue: 'food_delivery',
        at: DateTime(2025, 12, 1),
        source: LearningSource.ai,
      );
      final action = const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy', category: 'food_delivery');
      await service.confirmFinancialEventClassification(action, at: DateTime(2026, 1, 1));
      await service.confirmFinancialEventClassification(action, at: DateTime(2026, 1, 2));

      final profile = await repo.getProfile('u1', 'swiggy');
      expect(profile!.category.confirmations, 2);
      expect((await repo.getCorrectionHistory('u1', 'swiggy')), hasLength(1));
    });

    test('confirmation of a user-set value creates no correction history', () async {
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 1),
      );
      await service.confirmFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 2),
      );
      expect(await repo.getCorrectionHistory('u1', 'amazon'), hasLength(1));
    });
  });

  group('correction', () {
    test('first correction on an empty profile records exactly one correction event', () async {
      final result = await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 1),
      );

      expect(result.correctedFields, [LearnedFieldType.category]);
      expect(result.correctionsRecorded, 1);
      expect(result.confirmationsRecorded, 0);

      final history = await repo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(1));
      expect(history.first.oldValue, isNull);
      expect(history.first.newValue, 'shopping');
    });

    test('correction chain Shopping -> Food -> Grocery preserves full history', () async {
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'Shopping'),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'Food'),
        at: DateTime(2026, 1, 2),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'Grocery'),
        at: DateTime(2026, 1, 3),
      );

      final history = await repo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(3));
      expect(history.map((e) => e.newValue), ['Shopping', 'Food', 'Grocery']);
      expect(history[1].oldValue, 'Shopping');
      expect(history[2].oldValue, 'Food');

      final profile = await repo.getProfile('u1', 'amazon');
      expect(profile!.category.value, 'Grocery');
      expect(profile.category.corrections, 3);
    });

    test('individual field corrections: category, merchantType, paymentProvider, paymentMethod, subcategory', () async {
      const merchant = 'Zomato';
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: merchant, category: 'food'),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: merchant, subcategory: 'dining_out'),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: merchant, merchantType: MerchantType.business),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: merchant, paymentProvider: PaymentProvider.phonePe),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: merchant, paymentMethod: PaymentMethod.upi),
        at: DateTime(2026, 1, 1),
      );

      final profile = await repo.getProfile('u1', 'zomato');
      expect(profile!.category.value, 'food');
      expect(profile.subcategory.value, 'dining_out');
      expect(profile.merchantType.value, MerchantType.business);
      expect(profile.paymentProvider.value, PaymentProvider.phonePe);
      expect(profile.paymentMethod.value, PaymentMethod.upi);
    });

    test('same-value correction is treated as a confirmation, not a meaningless correction', () async {
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 1),
      );
      final result = await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 2),
      );

      expect(result.correctedFields, isEmpty);
      expect(result.confirmedFields, [LearnedFieldType.category]);

      final history = await repo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(1), reason: 'no second correction event for an unchanged value');

      final profile = await repo.getProfile('u1', 'amazon');
      expect(profile!.category.corrections, 1);
      expect(profile.category.confirmations, 1);
    });

    test('correction-after-confirmation then confirmation-after-correction sequences', () async {
      const action1 = UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping');
      await service.confirmFinancialEventClassification(action1, at: DateTime(2026, 1, 1));

      const action2 = UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'electronics');
      final correctResult = await service.correctFinancialEventClassification(action2, at: DateTime(2026, 1, 2));
      expect(correctResult.correctedFields, [LearnedFieldType.category]);

      final confirmResult = await service.confirmFinancialEventClassification(action2, at: DateTime(2026, 1, 3));
      expect(confirmResult.confirmedFields, [LearnedFieldType.category]);

      final profile = await repo.getProfile('u1', 'amazon');
      expect(profile!.category.value, 'electronics');
      expect(profile.category.corrections, 1);
      expect(profile.category.confirmations, 1);

      final history = await repo.getCorrectionHistory('u1', 'amazon');
      expect(history, hasLength(1));
    });
  });

  group('provider guard', () {
    test('a payment provider name is rejected as a merchant identity for confirmation', () async {
      expect(
        () => service.confirmFinancialEventClassification(
          const UserLearningAction(userId: 'u1', rawMerchantName: 'PhonePe', category: 'transfers'),
        ),
        throwsArgumentError,
      );
    });

    test('a payment provider name is rejected as a merchant identity for correction', () async {
      expect(
        () => service.correctFinancialEventClassification(
          const UserLearningAction(userId: 'u1', rawMerchantName: 'Google Pay', category: 'transfers'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('merchant key normalization', () {
    test('Swiggy, SWIGGY, and "Swiggy Pvt Ltd" normalize to the same profile', () async {
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy', category: 'food'),
        at: DateTime(2026, 1, 1),
      );
      await service.confirmFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'SWIGGY', category: 'food'),
        at: DateTime(2026, 1, 2),
      );
      await service.confirmFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy Pvt Ltd', category: 'food'),
        at: DateTime(2026, 1, 3),
      );

      final profile = await repo.getProfile('u1', 'swiggy');
      expect(profile!.category.confirmations, 2);
      expect(profile.category.corrections, 1);
    });

    test('Swiggy and Swiggy Instamart stay distinct profiles', () async {
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy', category: 'food_delivery'),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy Instamart', category: 'groceries'),
        at: DateTime(2026, 1, 1),
      );

      expect((await repo.getProfile('u1', 'swiggy'))!.category.value, 'food_delivery');
      expect((await repo.getProfile('u1', 'swiggy instamart'))!.category.value, 'groceries');
    });
  });

  group('isolation and independence', () {
    test('two users acting on the same merchant name never see each other\'s data', () async {
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 1),
      );
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u2', rawMerchantName: 'Amazon', category: 'electronics'),
        at: DateTime(2026, 1, 1),
      );

      expect((await repo.getProfile('u1', 'amazon'))!.category.value, 'shopping');
      expect((await repo.getProfile('u2', 'amazon'))!.category.value, 'electronics');
      expect(await repo.getCorrectionHistory('u1', 'amazon'), hasLength(1));
      expect(await repo.getCorrectionHistory('u2', 'amazon'), hasLength(1));
    });

    test('correcting one field never mutates unrelated fields', () async {
      const merchant = 'Flipkart';
      await service.correctFinancialEventClassification(
        const UserLearningAction(
          userId: 'u1',
          rawMerchantName: merchant,
          category: 'shopping',
          merchantType: MerchantType.business,
          paymentProvider: PaymentProvider.phonePe,
          paymentMethod: PaymentMethod.upi,
          subcategory: 'electronics_store',
        ),
        at: DateTime(2026, 1, 1),
      );

      final before = await repo.getProfile('u1', 'flipkart');

      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: merchant, category: 'groceries'),
        at: DateTime(2026, 1, 2),
      );

      final after = await repo.getProfile('u1', 'flipkart');
      expect(after!.category.value, 'groceries');
      expect(after.merchantType.value, before!.merchantType.value);
      expect(after.paymentProvider.value, before.paymentProvider.value);
      expect(after.paymentMethod.value, before.paymentMethod.value);
      expect(after.subcategory.value, before.subcategory.value);
      expect(after.merchantType.corrections, before.merchantType.corrections);
      expect(after.paymentProvider.corrections, before.paymentProvider.corrections);
    });
  });

  group('empty / null actions', () {
    test('an action naming no fields is a safe no-op for confirmation', () async {
      final result = await service.confirmFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy'),
        at: DateTime(2026, 1, 1),
      );
      expect(result.isNoOp, isTrue);
      expect(await repo.getProfile('u1', 'swiggy'), isNull);
    });

    test('an action naming no fields is a safe no-op for correction', () async {
      final result = await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy'),
        at: DateTime(2026, 1, 1),
      );
      expect(result.isNoOp, isTrue);
      expect(await repo.getCorrectionHistory('u1', 'swiggy'), isEmpty);
    });
  });

  group('atomic-failure leaves no partial state', () {
    test('a failure mid-transaction leaves the service\'s view of the profile unchanged', () async {
      final dao = MerchantLearningDao(db);
      await service.correctFinancialEventClassification(
        const UserLearningAction(userId: 'u1', rawMerchantName: 'Amazon', category: 'shopping'),
        at: DateTime(2026, 1, 1),
      );

      Object? caught;
      try {
        await dao.transaction((txnDao) async {
          final profile = await txnDao.getOrCreateProfile('u1', 'amazon');
          await txnDao.saveProfile(
            profile.copyWith(category: profile.category.correctedTo('electronics', DateTime(2026, 2, 1))),
          );
          throw StateError('simulated failure before correction history is appended');
        });
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>());
      final profile = await repo.getProfile('u1', 'amazon');
      expect(profile!.category.value, 'shopping', reason: 'partial transaction must have rolled back');
      expect(await repo.getCorrectionHistory('u1', 'amazon'), hasLength(1));
    });
  });

  group('structural exclusion of hard SMS evidence', () {
    test('UserLearningAction has no way to carry amount/direction/account/status/reference/raw text', () {
      // This is a structural, compile-time guarantee, not a runtime check:
      // UserLearningAction's constructor only accepts userId, rawMerchantName,
      // merchantType, category, subcategory, paymentProvider, paymentMethod.
      // Uncommenting any line below fails to compile because no such named
      // parameter exists on UserLearningAction:
      //
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', amount: 100);
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', direction: 'debit');
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', account: '1234');
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', status: 'pending');
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', reference: 'REF1');
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', smsBody: 'text');
      // UserLearningAction(userId: 'u1', rawMerchantName: 'x', otp: '123456');
      const action = UserLearningAction(userId: 'u1', rawMerchantName: 'Swiggy', category: 'food');
      expect(action.userId, 'u1');
    });
  });
}
