/// One participant's share of a split [Expense]. Embedded directly on the
/// expense document (not its own subcollection) since this is the fixed
/// definition of who owes what — the corresponding [Installment] (via
/// `OwnerType.splitExpense`) is the payable/trackable projection of the same
/// share, kept in step by [ExpenseRepository].
class ExpenseParticipant {
  ExpenseParticipant({
    required this.name,
    required this.share,
    this.personId,
    this.installmentId,
    this.isMe = false,
  });

  /// Null when the participant isn't tracked as a [Person] (e.g. the payer
  /// themselves, or someone deliberately left untracked).
  final String? personId;

  /// Display name — always populated, even for a linked [Person], so the
  /// UI never has to join back to the people collection just to render a
  /// participant list.
  final String name;

  /// This participant's portion of the expense's total, in the same
  /// currency unit as [Expense.totalAmount]. Always positive.
  final double share;

  /// The [Installment] tracking this participant's settlement — null until
  /// [ExpenseRepository.createExpense] generates the schedule, and always
  /// null for [isMe] (nothing is ever "collected" from yourself).
  final String? installmentId;

  /// Whether this is the permanent "Me" participant representing the
  /// payer's own share (see `Expense.myShare`). Defaults to `false` so
  /// documents/tests written before this field existed still deserialize
  /// correctly.
  final bool isMe;

  factory ExpenseParticipant.fromMap(Map<String, dynamic> map) {
    return ExpenseParticipant(
      personId: map['personId'] as String?,
      name: map['name'] as String,
      share: (map['share'] as num).toDouble(),
      installmentId: map['installmentId'] as String?,
      isMe: map['isMe'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'personId': personId,
      'name': name,
      'share': share,
      'installmentId': installmentId,
      'isMe': isMe,
    };
  }

  ExpenseParticipant copyWith({String? installmentId}) {
    return ExpenseParticipant(
      personId: personId,
      name: name,
      share: share,
      installmentId: installmentId ?? this.installmentId,
      isMe: isMe,
    );
  }
}
