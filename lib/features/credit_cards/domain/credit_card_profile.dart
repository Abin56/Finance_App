import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'card_network.dart';
import 'credit_card_status.dart';

/// The credit-card-specific settings layered onto an existing [Account] —
/// one [CreditCardProfile] per card [accountId], 1:1. Purchases on this card
/// are simply [Transaction]s where `transaction.accountId == accountId`, so
/// this profile only carries what a plain [Account] doesn't already know:
/// the statement cycle and its limits. [Account.currentBalance] keeps
/// tracking the card's running balance exactly as it does for any other
/// account — this profile never duplicates that.
class CreditCardProfile extends SoftDeletableEntity {
  CreditCardProfile({
    required this.id,
    required this.accountId,
    required this.statementDay,
    required this.paymentDueDay,
    required this.creditLimit,
    required this.createdAt,
    this.minimumDuePercent,
    this.autoPay = false,
    this.status = CreditCardStatus.active,
    this.cardNetwork,
    this.lastFourDigits,
    this.annualFee = 0,
    this.joiningFee = 0,
    this.interestRatePercent,
    this.rewardNotes,
    this.autoDebitAccount,
    this.cardHolderName,
  });

  @override
  final String id;

  /// The [Account] this profile extends — one credit card IS one account.
  final String accountId;

  /// Day of month (1-31) a statement closes on. Clamped to the shorter
  /// month when it doesn't exist (e.g. 31 in February) — see
  /// `StatementPeriod`'s month-clamping logic, mirroring
  /// `BillRecurrence.nextDueDate`.
  int statementDay;

  /// Day of month (1-31) in the month *after* the statement closes that
  /// payment is due — e.g. statement day 17, due day 5 means "17th closes,
  /// pay by the 5th of the following month."
  int paymentDueDay;

  double creditLimit;

  /// Percentage (0-100) of a statement's total used to compute its
  /// Minimum Due when generated. Null means minimum-due tracking is off for
  /// this card.
  double? minimumDuePercent;

  /// Informational only — this app has no background jobs, so nothing
  /// executes an automatic payment; it's surfaced in the UI as a flag the
  /// user set for their own reference.
  bool autoPay;

  /// Lifecycle state — active by default; [CreditCardStatus.closed]/
  /// [CreditCardStatus.cancelled] mark a card that's no longer in use. Kept
  /// as an explicit field (not derived) since only the user knows a card was
  /// closed. Defaults to [CreditCardStatus.active] for documents written
  /// before this field existed.
  CreditCardStatus status;

  /// Display/reference metadata — none of this feeds statement generation
  /// or payment logic, mirroring `Emi`'s bank/charges metadata fields.
  CardNetwork? cardNetwork;
  String? lastFourDigits;
  double annualFee;
  double joiningFee;

  /// Reference only — this app has no APR/interest-calculation engine, so
  /// this is never used in any computation (same posture as
  /// `Statement.interestCharged`, which is a manually-logged amount).
  double? interestRatePercent;
  String? rewardNotes;

  /// Only meaningful alongside [autoPay] — a free-text note on which
  /// account auto-debit draws from, informational only.
  String? autoDebitAccount;

  /// Display-only — printed name on the physical card, distinct from the
  /// linked account's [Account.name] (the card's nickname).
  String? cardHolderName;

  final DateTime createdAt;

  factory CreditCardProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return CreditCardProfile(
      id: snapshot.id,
      accountId: data['accountId'] as String,
      statementDay: (data['statementDay'] as num).toInt(),
      paymentDueDay: (data['paymentDueDay'] as num).toInt(),
      creditLimit: (data['creditLimit'] as num).toDouble(),
      minimumDuePercent: (data['minimumDuePercent'] as num?)?.toDouble(),
      autoPay: data['autoPay'] as bool? ?? false,
      status: CreditCardStatusX.fromName(data['status'] as String? ?? CreditCardStatus.active.name),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      cardNetwork: CardNetworkX.fromName(data['cardNetwork'] as String?),
      lastFourDigits: data['lastFourDigits'] as String?,
      annualFee: (data['annualFee'] as num?)?.toDouble() ?? 0,
      joiningFee: (data['joiningFee'] as num?)?.toDouble() ?? 0,
      interestRatePercent: (data['interestRatePercent'] as num?)?.toDouble(),
      rewardNotes: data['rewardNotes'] as String?,
      autoDebitAccount: data['autoDebitAccount'] as String?,
      cardHolderName: data['cardHolderName'] as String?,
    )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'accountId': accountId,
      'statementDay': statementDay,
      'paymentDueDay': paymentDueDay,
      'creditLimit': creditLimit,
      'minimumDuePercent': minimumDuePercent,
      'autoPay': autoPay,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'cardNetwork': cardNetwork?.name,
      'lastFourDigits': lastFourDigits,
      'annualFee': annualFee,
      'joiningFee': joiningFee,
      'interestRatePercent': interestRatePercent,
      'rewardNotes': rewardNotes,
      'autoDebitAccount': autoDebitAccount,
      'cardHolderName': cardHolderName,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
