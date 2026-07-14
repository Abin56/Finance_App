import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import 'emi_interest.dart';
import 'emi_loan_type.dart';
import 'emi_status.dart';

/// A recurring monthly (or weekly/custom) payment obligation — a loan
/// you're repaying in installments — tracked through a linked
/// `PaymentSchedule` (see [scheduleId]) rather than a cached balance, same
/// posture as `Loan`. Standalone from Lending's `Loan`: EMI always repays
/// via installments (there's no one-time mode), and carries its own
/// lender/category metadata.
class Emi extends SoftDeletableEntity {
  Emi({
    required this.id,
    required this.name,
    required this.principalAmount,
    required this.startDate,
    required this.installmentFrequency,
    required this.installmentCount,
    required this.endDate,
    required this.scheduleId,
    required this.createdAt,
    this.lenderName,
    this.categoryId,
    this.interest,
    this.notes = '',
    this.isClosed = false,
    this.loanNumber,
    this.loanType = EmiLoanType.other,
    this.branch,
    this.customerId,
    this.sanctionDate,
    this.disbursementDate,
    this.processingFee = 0,
    this.insuranceAmount = 0,
    this.extraCharges = 0,
    this.foreclosureAmount,
    this.prepaymentCharges,
    this.isAutoDebitEnabled = false,
    this.autoDebitAccount,
    this.isDefaulted = false,
    this.linkedCreditCardId,
    this.dueDayOfMonth,
  });

  @override
  final String id;
  String name;
  String? lenderName;
  String? categoryId;

  /// Bank/lender-side reference metadata — display-only, no effect on the
  /// payment schedule or interest math.
  String? loanNumber;
  EmiLoanType loanType;
  String? branch;
  String? customerId;
  DateTime? sanctionDate;
  DateTime? disbursementDate;

  /// One-time charges recorded for reference — not part of the amortized
  /// principal/interest schedule, so they don't feed `InterestCalculator`.
  double processingFee;
  double insuranceAmount;
  double extraCharges;
  double? foreclosureAmount;
  double? prepaymentCharges;

  /// Informational only — this app has no bank integration, so enabling
  /// this never triggers an actual auto-debit.
  bool isAutoDebitEnabled;
  String? autoDebitAccount;

  /// Explicit user action, same posture as [isClosed] — takes precedence
  /// over an overdue-installment-derived status in [statusGiven].
  bool isDefaulted;

  /// The `CreditCardProfile.id` this EMI was converted from (e.g. a
  /// purchase turned into a fixed-tenure EMI) — purely a reference link, no
  /// effect on this EMI's own schedule/interest math. When set,
  /// `creditCardStandingProvider` restores the linked card's available
  /// credit as this EMI's principal is paid down (see
  /// `principalRestoredForCardProvider`).
  String? linkedCreditCardId;

  /// Locked once any payment has been recorded — see `EmiRepository.editEmi`.
  double principalAmount;

  /// Set at creation; may change later via `EmiRepository.editEmiTerms`,
  /// which re-amortizes the outstanding principal over the unpaid tail of
  /// the schedule and regenerates those installments — already-paid
  /// installments are never touched.
  EmiInterest? interest;

  /// Immutable after creation — also seeds the linked schedule's
  /// `firstDueDate`. This is "First EMI Date" in the UI: installment #1
  /// always falls exactly here, regardless of [dueDayOfMonth].
  final DateTime startDate;

  /// The fixed day of the month (1-31) every installment *after* the first
  /// lands on — e.g. 5 means every EMI from #2 onward is due on the 5th,
  /// clamped to shorter months. Null means "no fixed day was chosen": every
  /// installment's day-of-month simply carries forward from [startDate],
  /// exactly as this app behaved before this field existed — see
  /// `InstallmentRepository.generateInstallments`'s `dueDayOfMonth` param.
  int? dueDayOfMonth;

  /// Set at creation; may change later via `EmiRepository.editEmiTerms`
  /// (see [interest]).
  ScheduleType installmentFrequency;

  /// Set at creation; may change later via `EmiRepository.editEmiTerms`
  /// (see [interest]) — can only grow to at least the number of
  /// installments already settled (paid or partially paid), never shrink
  /// below that.
  int installmentCount;

  /// The last generated installment's due date, captured at creation and
  /// recomputed by `EmiRepository.editEmiTerms` whenever the schedule is
  /// regenerated. Stored (unlike `Loan`, which has no "end date" concept)
  /// because EMI list screens show many EMIs at once — re-streaming every
  /// schedule's installments just to display an end date would be wasteful.
  DateTime endDate;

  String notes;

  /// The `PaymentSchedule.id` this EMI's payments are tracked through.
  final String scheduleId;

  /// Explicit user action ("Close EMI") — not derived, since "fully paid"
  /// and "closed" are different concepts.
  bool isClosed;

  final DateTime createdAt;

  /// This EMI's current standing. Requires the caller to supply the linked
  /// schedule's installments (unlike `Bill.status`'s zero-arg getter) since
  /// an EMI's payment state lives on separate `Installment` documents.
  EmiStatus statusGiven(List<Installment> installments) {
    if (isClosed) return EmiStatus.closed;
    if (isDefaulted) return EmiStatus.defaulted;
    final hasOverdue = installments.any((i) => i.status == InstallmentStatus.overdue);
    return hasOverdue ? EmiStatus.overdue : EmiStatus.active;
  }

  factory Emi.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Emi(
      id: snapshot.id,
      name: data['name'] as String,
      lenderName: data['lenderName'] as String?,
      categoryId: data['categoryId'] as String?,
      principalAmount: (data['principalAmount'] as num).toDouble(),
      interest: data['interest'] == null ? null : EmiInterest.fromMap(data['interest'] as Map<String, dynamic>),
      startDate: (data['startDate'] as Timestamp).toDate(),
      installmentFrequency: ScheduleTypeX.fromName(data['installmentFrequency'] as String),
      installmentCount: (data['installmentCount'] as num).toInt(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      notes: data['notes'] as String? ?? '',
      scheduleId: data['scheduleId'] as String,
      isClosed: data['isClosed'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      loanNumber: data['loanNumber'] as String?,
      loanType: EmiLoanTypeX.fromName(data['loanType'] as String?),
      branch: data['branch'] as String?,
      customerId: data['customerId'] as String?,
      sanctionDate: (data['sanctionDate'] as Timestamp?)?.toDate(),
      disbursementDate: (data['disbursementDate'] as Timestamp?)?.toDate(),
      processingFee: (data['processingFee'] as num?)?.toDouble() ?? 0,
      insuranceAmount: (data['insuranceAmount'] as num?)?.toDouble() ?? 0,
      extraCharges: (data['extraCharges'] as num?)?.toDouble() ?? 0,
      foreclosureAmount: (data['foreclosureAmount'] as num?)?.toDouble(),
      prepaymentCharges: (data['prepaymentCharges'] as num?)?.toDouble(),
      isAutoDebitEnabled: data['isAutoDebitEnabled'] as bool? ?? false,
      autoDebitAccount: data['autoDebitAccount'] as String?,
      isDefaulted: data['isDefaulted'] as bool? ?? false,
      linkedCreditCardId: data['linkedCreditCardId'] as String?,
      dueDayOfMonth: (data['dueDayOfMonth'] as num?)?.toInt(),
    )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'lenderName': lenderName,
      'categoryId': categoryId,
      'principalAmount': principalAmount,
      'interest': interest?.toMap(),
      'startDate': Timestamp.fromDate(startDate),
      'installmentFrequency': installmentFrequency.name,
      'installmentCount': installmentCount,
      'endDate': Timestamp.fromDate(endDate),
      'notes': notes,
      'scheduleId': scheduleId,
      'isClosed': isClosed,
      'createdAt': Timestamp.fromDate(createdAt),
      'loanNumber': loanNumber,
      'loanType': loanType.name,
      'branch': branch,
      'customerId': customerId,
      'sanctionDate': sanctionDate == null ? null : Timestamp.fromDate(sanctionDate!),
      'disbursementDate': disbursementDate == null ? null : Timestamp.fromDate(disbursementDate!),
      'processingFee': processingFee,
      'insuranceAmount': insuranceAmount,
      'extraCharges': extraCharges,
      'foreclosureAmount': foreclosureAmount,
      'prepaymentCharges': prepaymentCharges,
      'isAutoDebitEnabled': isAutoDebitEnabled,
      'autoDebitAccount': autoDebitAccount,
      'isDefaulted': isDefaulted,
      'linkedCreditCardId': linkedCreditCardId,
      'dueDayOfMonth': dueDayOfMonth,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
