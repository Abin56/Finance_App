import 'learning_source.dart';

/// The field of a `MerchantLearningProfile` a correction/confirmation
/// applies to. Kept as a closed enum (rather than a free-text field name) so
/// a `CorrectionEvent`/`MerchantFieldObservation` can never silently drift
/// onto a field this layer wasn't built to reason about — critically,
/// nothing here ever names amount/direction/account/status/reference, since
/// those are hard SMS evidence this layer must never touch.
enum LearnedFieldType {
  merchantType,
  category,
  subcategory,
  paymentProvider,
  paymentMethod,
}

/// One learned value for a merchant, plus how it got there. `confirmations`
/// and `corrections` are kept separate (rather than folded into a single
/// counter) because they answer different questions for
/// `LearningConfidence`: how consistent has this value been, versus how
/// often has the user actively overturned it.
class LearnedField<T> {
  const LearnedField({
    this.value,
    this.source = LearningSource.inference,
    this.confirmations = 0,
    this.corrections = 0,
    this.lastUpdatedAt,
  });

  final T? value;
  final LearningSource source;
  final int confirmations;
  final int corrections;
  final DateTime? lastUpdatedAt;

  bool get hasValue => value != null;

  /// The user (or a deterministic re-derivation) saw the same [value] again
  /// and didn't change it — strengthens confidence without touching the
  /// correction count.
  LearnedField<T> confirmedAt(DateTime at, {LearningSource? source}) {
    return LearnedField<T>(
      value: value,
      source: source ?? this.source,
      confirmations: confirmations + 1,
      corrections: corrections,
      lastUpdatedAt: at,
    );
  }

  /// The user (or a re-run of AI inference) replaced [value] with
  /// [newValue]. Resets `confirmations` to 0: the new value hasn't itself
  /// been confirmed yet, and carrying the old count forward would overstate
  /// confidence in a value that has never actually been seen before.
  LearnedField<T> correctedTo(
    T newValue,
    DateTime at, {
    LearningSource source = LearningSource.user,
  }) {
    return LearnedField<T>(
      value: newValue,
      source: source,
      confirmations: 0,
      corrections: corrections + 1,
      lastUpdatedAt: at,
    );
  }
}
