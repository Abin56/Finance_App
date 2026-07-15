import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../emi/domain/emi.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../lending/domain/loan.dart';
import '../../../lending/presentation/providers/loan_providers.dart';

/// "Which loan / which payment is this for?" picker shown before
/// `RecordLoanPaymentSheet` when converting an SMS into a Loan Payment —
/// an SMS never names a specific loan, so the user picks one first, exactly
/// the two-step flow `MoneyReceivedSheet` already uses for the same
/// ambiguity (see its `ReceiptTargetKind.loanInstallment` fields).
class SmsLoanPickerSheet extends ConsumerStatefulWidget {
  const SmsLoanPickerSheet({super.key});

  static Future<(Loan, Installment)?> show(BuildContext context) {
    return showModalBottomSheet<(Loan, Installment)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SmsLoanPickerSheet(),
    );
  }

  @override
  ConsumerState<SmsLoanPickerSheet> createState() => _SmsLoanPickerSheetState();
}

class _SmsLoanPickerSheetState extends ConsumerState<SmsLoanPickerSheet> {
  String? _loanId;
  String? _installmentId;

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(activeLoansProvider);
    final selectedLoan = loans.where((l) => l.id == _loanId).firstOrNull;
    final installments = selectedLoan == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(selectedLoan.scheduleId)).value ?? const [];
    final unpaid = installments.where((i) => i.remainingAmount > 0).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final selectedInstallment = unpaid.where((i) => i.id == _installmentId).firstOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Which loan is this for?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSizes.lg),
          DropdownButtonFormField<String>(
            initialValue: _loanId,
            decoration: const InputDecoration(labelText: 'Loan'),
            items: [
              for (final loan in loans)
                DropdownMenuItem(
                  value: loan.id,
                  child: Text(loan.name?.isNotEmpty == true ? loan.name! : CurrencyFormatter.instance.format(loan.loanAmount)),
                ),
            ],
            onChanged: (value) => setState(() {
              _loanId = value;
              _installmentId = null;
            }),
          ),
          if (selectedLoan != null) ...[
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<String>(
              initialValue: _installmentId,
              decoration: const InputDecoration(labelText: 'Which payment is this for?'),
              items: [
                for (final installment in unpaid)
                  DropdownMenuItem(
                    value: installment.id,
                    child: Text(
                      '${installment.dueDate.fullDate} · ${CurrencyFormatter.instance.format(installment.remainingAmount)} left',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _installmentId = value),
            ),
          ],
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(
            label: 'Continue',
            onPressed: selectedLoan == null || selectedInstallment == null
                ? null
                : () => Navigator.of(context).pop((selectedLoan, selectedInstallment)),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }
}

/// Same idea as [SmsLoanPickerSheet], for EMI Payment conversions.
class SmsEmiPickerSheet extends ConsumerStatefulWidget {
  const SmsEmiPickerSheet({super.key});

  static Future<(Emi, Installment)?> show(BuildContext context) {
    return showModalBottomSheet<(Emi, Installment)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SmsEmiPickerSheet(),
    );
  }

  @override
  ConsumerState<SmsEmiPickerSheet> createState() => _SmsEmiPickerSheetState();
}

class _SmsEmiPickerSheetState extends ConsumerState<SmsEmiPickerSheet> {
  String? _emiId;
  String? _installmentId;

  @override
  Widget build(BuildContext context) {
    final emis = ref.watch(activeEmisProvider);
    final selectedEmi = emis.where((e) => e.id == _emiId).firstOrNull;
    final installments = selectedEmi == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(selectedEmi.scheduleId)).value ?? const [];
    final unpaid = installments.where((i) => i.remainingAmount > 0).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final selectedInstallment = unpaid.where((i) => i.id == _installmentId).firstOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Which EMI is this for?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSizes.lg),
          DropdownButtonFormField<String>(
            initialValue: _emiId,
            decoration: const InputDecoration(labelText: 'EMI'),
            items: [
              for (final emi in emis) DropdownMenuItem(value: emi.id, child: Text(emi.name)),
            ],
            onChanged: (value) => setState(() {
              _emiId = value;
              _installmentId = null;
            }),
          ),
          if (selectedEmi != null) ...[
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<String>(
              initialValue: _installmentId,
              decoration: const InputDecoration(labelText: 'Which payment is this for?'),
              items: [
                for (final installment in unpaid)
                  DropdownMenuItem(
                    value: installment.id,
                    child: Text(
                      '${installment.dueDate.fullDate} · ${CurrencyFormatter.instance.format(installment.remainingAmount)} left',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _installmentId = value),
            ),
          ],
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(
            label: 'Continue',
            onPressed: selectedEmi == null || selectedInstallment == null
                ? null
                : () => Navigator.of(context).pop((selectedEmi, selectedInstallment)),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }
}
