import '../../../core/interest/interest_period.dart';
import '../../../core/interest/interest_type.dart';

/// Optional interest terms for a [Loan]. When present, `LoanRepository.createLoan`
/// runs `InterestCalculator` to produce the real amortization breakdown fed
/// into `InstallmentRepository.generateInstallments` — this is not
/// display-only metadata.
class LoanInterest {
  const LoanInterest({
    required this.type,
    required this.ratePercent,
    required this.period,
  });

  final InterestType type;
  final double ratePercent;
  final InterestPeriod period;

  factory LoanInterest.fromMap(Map<String, dynamic> map) => LoanInterest(
        type: InterestTypeX.fromName(map['type'] as String),
        ratePercent: (map['ratePercent'] as num).toDouble(),
        period: InterestPeriodX.fromName(map['period'] as String),
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'ratePercent': ratePercent,
        'period': period.name,
      };
}
