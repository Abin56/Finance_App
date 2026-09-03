import '../financial_event/merchant_type.dart';
import '../financial_event/payment_method.dart';
import '../financial_event/payment_provider.dart';
import '../merchant/merchant_key.dart';
import 'learned_field.dart';
import 'learning_source.dart';
import 'learning_update_result.dart';
import 'merchant_learning_profile.dart';
import 'merchant_learning_repository.dart';
import 'merchant_provider_guard.dart';
import 'user_learning_action.dart';

/// Converts an explicit user confirm/correct action into calls against
/// `MerchantLearningRepository`. This is a capture layer only: it never
/// decides what to learn, never runs off an SMS scan or AI inference, and
/// never creates a transaction/event/obligation — it only persists what a
/// caller (future UI) hands it as the direct result of a user tapping
/// "that's right" or "actually, this is X".
///
/// Never wired into `FinancialEventExtractor`, `AiCallNecessity`, or the AI
/// provider — those stay entirely untouched by this class.
class FinancialEventLearningService {
  const FinancialEventLearningService(this._repository);

  final MerchantLearningRepository _repository;

  /// Records the user reaffirming the fields present on [action] as
  /// correct, as-is. Every named field goes through `confirmField` — never
  /// `applyCorrection` — so no `CorrectionEvent` is ever created here, and
  /// fields absent from [action] are left completely untouched.
  Future<LearningUpdateResult> confirmFinancialEventClassification(
    UserLearningAction action, {
    DateTime? at,
  }) async {
    final merchantKey = _resolveMerchantKey(action.rawMerchantName);
    final timestamp = at ?? DateTime.now();
    final confirmed = <LearnedFieldType>[];

    Future<void> confirm<T>(LearnedFieldType field, T? value) async {
      if (value == null) return;
      await _repository.confirmField<T>(
        userId: action.userId,
        merchantKey: merchantKey,
        field: field,
        at: timestamp,
        source: LearningSource.user,
      );
      confirmed.add(field);
    }

    await confirm<MerchantType>(LearnedFieldType.merchantType, action.merchantType);
    await confirm<String>(LearnedFieldType.category, action.category);
    await confirm<String>(LearnedFieldType.subcategory, action.subcategory);
    await confirm<PaymentProvider>(LearnedFieldType.paymentProvider, action.paymentProvider);
    await confirm<PaymentMethod>(LearnedFieldType.paymentMethod, action.paymentMethod);

    if (confirmed.isEmpty) {
      return LearningUpdateResult.empty(merchantKey);
    }
    return LearningUpdateResult(
      merchantKey: merchantKey,
      confirmedFields: confirmed,
      correctedFields: const [],
      confirmationsRecorded: confirmed.length,
      correctionsRecorded: 0,
      explanation: 'Confirmed ${_describe(confirmed)} for "$merchantKey".',
    );
  }

  /// Records the user changing the fields present on [action]. A field
  /// whose new value is identical to the profile's current value is treated
  /// as a confirmation instead of a meaningless correction — no
  /// `CorrectionEvent` is created for it. Every other named field goes
  /// through `applyCorrection`, which atomically updates the value and
  /// appends exactly one `CorrectionEvent` preserving the old value. Fields
  /// absent from [action] are left completely untouched.
  Future<LearningUpdateResult> correctFinancialEventClassification(
    UserLearningAction action, {
    DateTime? at,
  }) async {
    final merchantKey = _resolveMerchantKey(action.rawMerchantName);
    final timestamp = at ?? DateTime.now();
    final MerchantLearningProfile? current = await _repository.getProfile(
      action.userId,
      merchantKey,
    );

    final confirmed = <LearnedFieldType>[];
    final corrected = <LearnedFieldType>[];

    Future<void> correct<T>(
      LearnedFieldType field,
      T? newValue,
      LearnedField<T>? currentField,
    ) async {
      if (newValue == null) return;
      if (currentField != null && currentField.hasValue && currentField.value == newValue) {
        await _repository.confirmField<T>(
          userId: action.userId,
          merchantKey: merchantKey,
          field: field,
          at: timestamp,
          source: LearningSource.user,
        );
        confirmed.add(field);
        return;
      }
      await _repository.applyCorrection<T>(
        userId: action.userId,
        merchantKey: merchantKey,
        field: field,
        newValue: newValue,
        at: timestamp,
        source: LearningSource.user,
      );
      corrected.add(field);
    }

    await correct<MerchantType>(LearnedFieldType.merchantType, action.merchantType, current?.merchantType);
    await correct<String>(LearnedFieldType.category, action.category, current?.category);
    await correct<String>(LearnedFieldType.subcategory, action.subcategory, current?.subcategory);
    await correct<PaymentProvider>(
      LearnedFieldType.paymentProvider,
      action.paymentProvider,
      current?.paymentProvider,
    );
    await correct<PaymentMethod>(
      LearnedFieldType.paymentMethod,
      action.paymentMethod,
      current?.paymentMethod,
    );

    if (confirmed.isEmpty && corrected.isEmpty) {
      return LearningUpdateResult.empty(merchantKey);
    }

    final parts = <String>[];
    if (corrected.isNotEmpty) parts.add('corrected ${_describe(corrected)}');
    if (confirmed.isNotEmpty) parts.add('confirmed ${_describe(confirmed)} (already that value)');

    return LearningUpdateResult(
      merchantKey: merchantKey,
      confirmedFields: confirmed,
      correctedFields: corrected,
      confirmationsRecorded: confirmed.length,
      correctionsRecorded: corrected.length,
      explanation: '${parts.join('; ')} for "$merchantKey".',
    );
  }

  String _resolveMerchantKey(String rawMerchantName) {
    final key = MerchantKey.normalize(rawMerchantName);
    if (key == null) {
      throw ArgumentError.value(
        rawMerchantName,
        'rawMerchantName',
        'does not normalize to a usable merchant key',
      );
    }
    if (MerchantProviderGuard.isProviderName(key)) {
      throw ArgumentError.value(
        rawMerchantName,
        'rawMerchantName',
        'is a payment provider, not a merchant — see MerchantProviderGuard',
      );
    }
    return key;
  }

  String _describe(List<LearnedFieldType> fields) => fields.map((f) => f.name).join(', ');
}
