import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Which way a [Loan] flows — chosen at creation, immutable thereafter
/// (mirrors [LoanRepaymentType]). Absent on a Firestore doc means [given],
/// since every `Loan` created before this field existed was always a
/// receivable.
enum LoanDirection { given, taken }

extension LoanDirectionX on LoanDirection {
  static LoanDirection fromName(String? name) =>
      LoanDirection.values.firstWhere((d) => d.name == name, orElse: () => LoanDirection.given);

  /// Label for the direction picker on the Add Loan form.
  String get formLabel => this == LoanDirection.given ? 'I Gave Money' : 'I Borrowed Money';

  /// Label for the direction badge shown on loan rows/detail.
  String get badgeLabel => this == LoanDirection.given ? 'You will receive' : 'You need to pay';

  Color get color => this == LoanDirection.given ? AppColors.credit : AppColors.debit;

  IconData get icon => this == LoanDirection.given ? Icons.call_made_rounded : Icons.call_received_rounded;
}
