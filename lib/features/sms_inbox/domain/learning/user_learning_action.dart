import '../financial_event/merchant_type.dart';
import '../financial_event/payment_method.dart';
import '../financial_event/payment_provider.dart';

/// An explicit user action confirming or correcting FlowFi's classification
/// of one merchant — the only input `FinancialEventLearningService` accepts.
///
/// Deliberately carries only the fields `LearnedFieldType` knows how to
/// learn, plus the merchant identity itself (the raw name the user is
/// confirming/correcting, normalized to a `MerchantKey` by the service).
/// Hard SMS evidence — amount, direction, account, status, reference, the
/// raw SMS body, OTP/PIN/CVV, phone/card numbers, AI prompts/responses —
/// has no field here at all, so an action touching any of it cannot be
/// constructed; there is nothing to runtime-check.
class UserLearningAction {
  const UserLearningAction({
    required this.userId,
    required this.rawMerchantName,
    this.merchantType,
    this.category,
    this.subcategory,
    this.paymentProvider,
    this.paymentMethod,
  });

  final String userId;

  /// Free-text merchant name as the user typed or selected it. Normalized
  /// via `MerchantKey.normalize` and checked against `MerchantProviderGuard`
  /// by the service before anything reaches the repository — this class
  /// does not enforce that itself, matching how `MerchantLearningProfile`
  /// defers the same enforcement to its write boundary.
  final String rawMerchantName;

  final MerchantType? merchantType;
  final String? category;
  final String? subcategory;
  final PaymentProvider? paymentProvider;
  final PaymentMethod? paymentMethod;

  /// True when the user named no field at all — a safe no-op, not an error.
  bool get isEmpty =>
      merchantType == null &&
      category == null &&
      subcategory == null &&
      paymentProvider == null &&
      paymentMethod == null;
}
