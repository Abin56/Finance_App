import 'learned_field.dart';
import 'learning_source.dart';

/// One structured, privacy-safe record of a value changing for a merchant —
/// either the user correcting a suggestion or a re-run of AI/inference
/// changing its own prior guess. Deliberately holds only normalized
/// structured fields (merchant key, category/subcategory ids, provider,
/// method) and never raw SMS text, matching this feature's "never store the
/// SMS body outside the inbox item itself" boundary (see
/// `SmsBodyRedactor`/`MerchantMemory`'s own doc comment).
class CorrectionEvent {
  const CorrectionEvent({
    required this.merchantKey,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
    this.source = LearningSource.user,
  });

  final String merchantKey;
  final LearnedFieldType field;

  /// `null` when the field had no prior value (a first-time classification
  /// rather than a genuine correction).
  final String? oldValue;
  final String? newValue;
  final DateTime timestamp;
  final LearningSource source;

  bool get isFirstTimeClassification => oldValue == null;
}
