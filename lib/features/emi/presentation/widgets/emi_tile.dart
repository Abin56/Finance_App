import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../lending/presentation/widgets/loan_emi_ui.dart';
import '../../domain/emi.dart';
import '../../domain/emi_loan_type.dart';
import '../../domain/emi_status.dart';
import '../providers/emi_providers.dart';

/// Non-routine states only; an active EMI carries no badge.
List<LoanEmiBadge> emiBadges(BuildContext context, EmiStatus status) {
  switch (status) {
    case EmiStatus.overdue:
      return const [LoanEmiBadge('Missed payment', AppColors.error)];
    case EmiStatus.defaulted:
      return const [LoanEmiBadge('Defaulted', AppColors.error)];
    case EmiStatus.completed:
      return const [LoanEmiBadge('Completed', AppColors.success)];
    case EmiStatus.closed:
      return [LoanEmiBadge('Closed', loanEmiNeutralBadgeColor(context))];
    case EmiStatus.active:
      return const [];
  }
}

/// "HDFC Card •••• 1234" for an EMI's linked card, or null.
String? emiLinkedCardLabel(WidgetRef ref, Emi emi) {
  final cardId = emi.linkedCreditCardId;
  if (cardId == null) return null;
  final name = ref.watch(accountForCardProvider(cardId))?.name ?? 'Credit card';
  final card = (ref.watch(creditCardsStreamProvider).value ?? const [])
      .where((c) => c.id == cardId)
      .firstOrNull;
  final last4 = card?.lastFourDigits;
  return last4 != null && last4.isNotEmpty ? '$name •••• $last4' : name;
}

/// EMI list card for the Loan & EMI screen — the twin of web's `EmiCard`,
/// built on the same [LoanEmiCard] as Loans. Swipeable to archive, handled
/// by the screen that owns the Dismissible key.
class EmiTile extends ConsumerWidget {
  const EmiTile({super.key, required this.emi, required this.onTap});

  final Emi emi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(emiStatusProvider(emi));
    final remaining = ref.watch(emiRemainingAmountProvider(emi));
    final paid = ref.watch(emiInstallmentsPaidProvider(emi));
    final installments =
        ref.watch(installmentsStreamProvider(emi.scheduleId)).value ??
        const [];
    final done = status == EmiStatus.closed || status == EmiStatus.completed;
    final sorted = [...installments]
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final next = done
        ? null
        : sorted
              .where((i) => !i.isSkipped && i.remainingAmount > 0)
              .firstOrNull;
    final cardLabel = emiLinkedCardLabel(ref, emi);
    final lender = emi.lenderName?.trim();
    final source = lender != null && lender.isNotEmpty
        ? lender
        : (cardLabel ?? emi.loanType.label);

    return LoanEmiCard(
      icon: emi.loanType == EmiLoanType.other
          ? LoanEmiCopy.emiIcon
          : emi.loanType.icon,
      name: emi.name,
      source: source,
      badges: emiBadges(context, status),
      outstandingLabel: LoanEmiCopy.outstanding,
      outstanding: remaining,
      nextAmount: next?.remainingAmount,
      nextDate: next?.dueDate,
      overdue:
          status == EmiStatus.overdue ||
          (next != null && loanEmiDaysUntil(next.dueDate) < 0),
      paid: paid,
      total: emi.installmentCount,
      links: [
        if (cardLabel != null && cardLabel != source)
          (Icons.credit_card_rounded, cardLabel),
      ],
      muted: status == EmiStatus.closed,
      onTap: onTap,
    );
  }
}
