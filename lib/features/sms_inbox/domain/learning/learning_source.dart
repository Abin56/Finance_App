/// Where a learned value came from — never a bare confidence number without
/// this, since "the user told us directly" and "AI guessed it" must never be
/// weighted the same when reconciling conflicting history.
enum LearningSource { user, ai, inference }

extension LearningSourceX on LearningSource {
  static LearningSource fromName(String? name) {
    if (name == null) return LearningSource.inference;
    return LearningSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LearningSource.inference,
    );
  }
}
