import '../../data/merchant_learning_dao.dart';
import '../financial_event/merchant_type.dart';
import '../financial_event/payment_method.dart';
import '../financial_event/payment_provider.dart';
import 'correction_event.dart';
import 'learned_field.dart';
import 'learning_source.dart';
import 'merchant_learning_profile.dart';
import 'merchant_provider_guard.dart';

/// Adapts `MerchantLearningDao`'s SQL-shaped CRUD onto the same domain-level
/// API `MerchantLearningStore` offers in-memory, so a caller never needs to
/// know a table exists. This is the persistent replacement for
/// `MerchantLearningStore` — same user/merchant isolation, same
/// `MerchantProviderGuard` enforcement at the write boundary, same
/// append-only correction history. It does not decide *what* to learn or
/// call AI; it only persists what a caller explicitly passes in.
class MerchantLearningRepository {
  const MerchantLearningRepository(this._dao);

  final MerchantLearningDao _dao;

  Future<MerchantLearningProfile?> getProfile(String userId, String merchantKey) =>
      _dao.getProfile(userId, merchantKey);

  Future<MerchantLearningProfile> getOrCreateProfile(
    String userId,
    String merchantKey,
  ) {
    _guard(merchantKey);
    return _dao.getOrCreateProfile(userId, merchantKey);
  }

  Future<List<MerchantLearningProfile>> listProfiles(String userId) =>
      _dao.listProfiles(userId);

  Future<void> deleteProfile(String userId, String merchantKey) =>
      _dao.deleteProfile(userId, merchantKey);

  Future<void> clearAllForUser(String userId) => _dao.clearAllForUser(userId);

  Future<List<CorrectionEvent>> getCorrectionHistory(
    String userId,
    String merchantKey, {
    LearnedFieldType? field,
  }) => _dao.getCorrectionHistory(userId, merchantKey, field: field);

  /// Records the user (or a re-run of inference) confirming the existing
  /// value of one field on [merchantKey]'s profile again — strengthens
  /// confidence without touching correction history, mirroring
  /// `LearnedField.confirmedAt`. Creates the profile first if it doesn't
  /// exist yet (an explicit confirmation is itself a reason to start
  /// tracking this merchant).
  Future<MerchantLearningProfile> confirmField<T>({
    required String userId,
    required String merchantKey,
    required LearnedFieldType field,
    required DateTime at,
    LearningSource? source,
  }) async {
    _guard(merchantKey);
    final profile = await _dao.getOrCreateProfile(userId, merchantKey);
    final updated = _applyToField<T>(
      profile,
      field,
      (current) => current.confirmedAt(at, source: source),
    );
    await _dao.saveProfile(updated);
    return updated;
  }

  /// Replaces one field's value with [newValue], atomically updating the
  /// profile row and appending a [CorrectionEvent] to history in a single
  /// sqflite transaction — a failure partway through leaves neither half
  /// applied (see `MerchantLearningDao.transaction`). This is the only path
  /// that should ever change a learned value away from what it currently is;
  /// [confirmField] never changes a value, only its own confidence.
  Future<MerchantLearningProfile> applyCorrection<T>({
    required String userId,
    required String merchantKey,
    required LearnedFieldType field,
    required T newValue,
    required DateTime at,
    LearningSource source = LearningSource.user,
  }) async {
    _guard(merchantKey);
    return _dao.transaction((txnDao) async {
      final profile = await txnDao.getOrCreateProfile(userId, merchantKey);
      final currentField = _readField<T>(profile, field);
      final oldValue = currentField.hasValue ? _encode(field, currentField.value as T) : null;
      final newValueEncoded = _encode(field, newValue);

      final updated = _applyToField<T>(
        profile,
        field,
        (current) => current.correctedTo(newValue, at, source: source),
      );
      await txnDao.saveProfile(updated);
      await txnDao.recordCorrection(
        userId,
        CorrectionEvent(
          merchantKey: merchantKey,
          field: field,
          oldValue: oldValue,
          newValue: newValueEncoded,
          timestamp: at,
          source: source,
        ),
      );
      return updated;
    });
  }

  void _guard(String merchantKey) {
    if (MerchantProviderGuard.isProviderName(merchantKey)) {
      throw ArgumentError.value(
        merchantKey,
        'merchantKey',
        'is a payment provider, not a merchant — see MerchantProviderGuard',
      );
    }
  }

  String _encode<T>(LearnedFieldType field, T value) {
    switch (field) {
      case LearnedFieldType.merchantType:
        return (value as MerchantType).name;
      case LearnedFieldType.category:
      case LearnedFieldType.subcategory:
        return value as String;
      case LearnedFieldType.paymentProvider:
        return (value as PaymentProvider).name;
      case LearnedFieldType.paymentMethod:
        return (value as PaymentMethod).name;
    }
  }

  LearnedField<T> _readField<T>(MerchantLearningProfile profile, LearnedFieldType field) {
    switch (field) {
      case LearnedFieldType.merchantType:
        return profile.merchantType as LearnedField<T>;
      case LearnedFieldType.category:
        return profile.category as LearnedField<T>;
      case LearnedFieldType.subcategory:
        return profile.subcategory as LearnedField<T>;
      case LearnedFieldType.paymentProvider:
        return profile.paymentProvider as LearnedField<T>;
      case LearnedFieldType.paymentMethod:
        return profile.paymentMethod as LearnedField<T>;
    }
  }

  MerchantLearningProfile _applyToField<T>(
    MerchantLearningProfile profile,
    LearnedFieldType field,
    LearnedField<T> Function(LearnedField<T> current) transform,
  ) {
    switch (field) {
      case LearnedFieldType.merchantType:
        return profile.copyWith(
          merchantType: transform(profile.merchantType as LearnedField<T>) as LearnedField<MerchantType>,
        );
      case LearnedFieldType.category:
        return profile.copyWith(
          category: transform(profile.category as LearnedField<T>) as LearnedField<String>,
        );
      case LearnedFieldType.subcategory:
        return profile.copyWith(
          subcategory: transform(profile.subcategory as LearnedField<T>) as LearnedField<String>,
        );
      case LearnedFieldType.paymentProvider:
        return profile.copyWith(
          paymentProvider: transform(profile.paymentProvider as LearnedField<T>) as LearnedField<PaymentProvider>,
        );
      case LearnedFieldType.paymentMethod:
        return profile.copyWith(
          paymentMethod: transform(profile.paymentMethod as LearnedField<T>) as LearnedField<PaymentMethod>,
        );
    }
  }
}
