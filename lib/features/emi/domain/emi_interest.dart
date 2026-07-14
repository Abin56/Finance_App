import '../../../core/interest/interest_period.dart';
import '../../../core/interest/interest_type.dart';

/// Optional interest terms for an [Emi]. When present, `EmiRepository.createEmi`
/// runs `InterestCalculator` to produce the real amortization breakdown fed
/// into `InstallmentRepository.generateInstallments` — not display-only
/// metadata. Kept as EMI's own copy rather than sharing `LoanInterest`,
/// matching this codebase's precedent of each feature owning its domain
/// types while composing the same core engines.
class EmiInterest {
  const EmiInterest({
    required this.type,
    required this.ratePercent,
    required this.period,
  });

  final InterestType type;
  final double ratePercent;
  final InterestPeriod period;

  factory EmiInterest.fromMap(Map<String, dynamic> map) => EmiInterest(
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
