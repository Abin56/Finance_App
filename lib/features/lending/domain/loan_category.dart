/// Which kind of loan this is — chosen at creation, immutable thereafter
/// (mirrors [LoanDirection]/[LoanRepaymentType]). Absent on a Firestore doc
/// means [personal], since every `Loan` created before this field existed
/// was always person-linked.
enum LoanCategory { personal, institutional }

extension LoanCategoryX on LoanCategory {
  static LoanCategory fromName(String? name) =>
      LoanCategory.values.firstWhere((c) => c.name == name, orElse: () => LoanCategory.personal);

  String get formLabel => this == LoanCategory.personal ? 'Personal' : 'Institution';
}
