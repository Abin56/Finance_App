import 'package:flutter/material.dart';

/// What kind of borrowing an [Emi] represents — display/filtering metadata
/// only, doesn't affect interest math or the payment schedule.
enum EmiLoanType { home, personal, vehicle, education, gold, business, creditCard, other }

extension EmiLoanTypeX on EmiLoanType {
  static EmiLoanType fromName(String? name) =>
      EmiLoanType.values.firstWhere((t) => t.name == name, orElse: () => EmiLoanType.other);

  String get label {
    switch (this) {
      case EmiLoanType.home:
        return 'Home Loan';
      case EmiLoanType.personal:
        return 'Personal Loan';
      case EmiLoanType.vehicle:
        return 'Vehicle Loan';
      case EmiLoanType.education:
        return 'Education Loan';
      case EmiLoanType.gold:
        return 'Gold Loan';
      case EmiLoanType.business:
        return 'Business Loan';
      case EmiLoanType.creditCard:
        return 'Credit Card';
      case EmiLoanType.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case EmiLoanType.home:
        return Icons.house_outlined;
      case EmiLoanType.personal:
        return Icons.person_outline_rounded;
      case EmiLoanType.vehicle:
        return Icons.directions_car_outlined;
      case EmiLoanType.education:
        return Icons.school_outlined;
      case EmiLoanType.gold:
        return Icons.diamond_outlined;
      case EmiLoanType.business:
        return Icons.business_center_outlined;
      case EmiLoanType.creditCard:
        return Icons.credit_card_outlined;
      case EmiLoanType.other:
        return Icons.account_balance_outlined;
    }
  }
}
