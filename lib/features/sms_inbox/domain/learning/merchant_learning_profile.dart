import '../financial_event/merchant_type.dart';
import '../financial_event/payment_method.dart';
import '../financial_event/payment_provider.dart';
import 'learned_field.dart';

/// Everything FlowFi has learned about one merchant for one user — a richer,
/// per-field successor to `MerchantMemory` (which only remembers a single
/// category per merchant/transaction-type pair). Never applied to a
/// transaction automatically: every consumer of this class only ever
/// produces a *suggestion* (see `AiCallReductionDecision`), exactly like
/// `MerchantCategorySuggester`/`CategoryResolver` already do.
///
/// [merchantKey] must be a `MerchantKey.normalize`d string that is not a
/// payment provider name — see `MerchantProviderGuard`. This class doesn't
/// enforce that itself (it has no dependency on where the key came from);
/// enforcement lives at the write boundary (`MerchantLearningStore.put`), the
/// same layering `MerchantMemoryDao` uses for its own invariants.
class MerchantLearningProfile {
  const MerchantLearningProfile({
    required this.userId,
    required this.merchantKey,
    this.merchantType = const LearnedField<MerchantType>(),
    this.category = const LearnedField<String>(),
    this.subcategory = const LearnedField<String>(),
    this.paymentProvider = const LearnedField<PaymentProvider>(),
    this.paymentMethod = const LearnedField<PaymentMethod>(),
  });

  final String userId;
  final String merchantKey;

  final LearnedField<MerchantType> merchantType;
  final LearnedField<String> category;
  final LearnedField<String> subcategory;
  final LearnedField<PaymentProvider> paymentProvider;
  final LearnedField<PaymentMethod> paymentMethod;

  MerchantLearningProfile copyWith({
    LearnedField<MerchantType>? merchantType,
    LearnedField<String>? category,
    LearnedField<String>? subcategory,
    LearnedField<PaymentProvider>? paymentProvider,
    LearnedField<PaymentMethod>? paymentMethod,
  }) {
    return MerchantLearningProfile(
      userId: userId,
      merchantKey: merchantKey,
      merchantType: merchantType ?? this.merchantType,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      paymentProvider: paymentProvider ?? this.paymentProvider,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}
