import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/models/payer_source.dart';
import '../../../../core/payment_schedule/domain/installment_settlement.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/payment_attribution_service.dart';
import '../../../../core/services/providers/payment_attribution_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan.dart';
import '../providers/loan_providers.dart';

/// Bottom sheet for settling a single lump-sum amount across a loan's
/// outstanding installments, oldest-due-first — the Loan counterpart to
/// [RecordEmiLumpSumSettlementSheet]. Fans one entered amount across as many
/// installments as it covers via [InstallmentSettlement.plan], letting the
/// last one touched be only partially paid. Routed through
/// [PaymentAttributionService.apply] exactly like [RecordLoanPaymentSheet],
/// so a Person payer still posts one combined ledger entry for the whole
/// settlement.
class RecordLoanLumpSumSettlementSheet extends ConsumerStatefulWidget {
  const RecordLoanLumpSumSettlementSheet({super.key, required this.loan});

  final Loan loan;

  static Future<void> show(BuildContext context, Loan loan) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => RecordLoanLumpSumSettlementSheet(loan: loan),
    );
  }

  @override
  ConsumerState<RecordLoanLumpSumSettlementSheet> createState() =>
      _RecordLoanLumpSumSettlementSheetState();
}

class _RecordLoanLumpSumSettlementSheetState
    extends ConsumerState<RecordLoanLumpSumSettlementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: ref.read(loanRemainingAmountProvider(widget.loan)).toStringAsFixed(2),
  );
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  late bool _someoneElsePaid = widget.loan.payerPersonId != null;
  late String? _selectedPersonId = widget.loan.payerPersonId;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  PayerSource _resolvePayer() {
    if (!_someoneElsePaid) return const PayerSource.self();
    final people = ref.read(peopleStreamProvider).value ?? const [];
    final person = people.where((p) => p.id == _selectedPersonId).first;
    return PayerSource.person(person);
  }

  String _resolveNote(PayerSource payer) {
    final typed = _noteController.text.trim();
    if (typed.isNotEmpty) return typed;
    if (payer case PersonPayerSource(:final person))
      return 'Paid by ${person.name}';
    return '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_someoneElsePaid && _selectedPersonId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose who paid')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final installments =
          ref.read(installmentsStreamProvider(widget.loan.scheduleId)).value ??
          const [];
      final outstanding =
          installments.where((i) => i.remainingAmount > 0).toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      final amount = double.parse(_amountController.text.trim());
      final plan = InstallmentSettlement.plan(outstanding, amount);
      final payer = _resolvePayer();
      final payerPersonId = switch (payer) {
        PersonPayerSource(:final person) => person.id,
        SelfPayerSource() => null,
      };

      final items = [
        for (final p in plan.portions)
          PaymentAttributionItem(
            obligationLabel: 'your loan payment',
            amount: p.portion,
            record: ({required amount, required date, required note}) => ref
                .read(
                  installmentPaymentRepositoryProvider((
                    scheduleId: p.installment.scheduleId,
                    installmentId: p.installment.id,
                  )),
                )
                .recordPayment(
                  p.installment,
                  amount: amount,
                  date: date,
                  note: note,
                  payerPersonId: payerPersonId,
                ),
          ),
      ];

      await ref
          .read(paymentAttributionServiceProvider)
          .apply(
            items: items,
            payer: payer,
            date: _date,
            note: _resolveNote(payer),
          );

      final refreshedInstallments = ref.read(installmentsStreamProvider(widget.loan.scheduleId)).value ?? const [];
      final nextUnpaid = refreshedInstallments.where((i) => i.remainingAmount > 0 && !i.isSkipped).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      final repository = ref.read(loanRepositoryProvider);
      if (nextUnpaid.isNotEmpty) {
        repository.rescheduleReminders(widget.loan, nextUnpaid.first.dueDate);
      } else {
        repository.cancelReminders(widget.loan.id);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not record payment: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalOutstanding = ref.watch(
      loanRemainingAmountProvider(widget.loan),
    );
    final installments =
        ref.watch(installmentsStreamProvider(widget.loan.scheduleId)).value ??
        const [];
    final outstanding =
        installments.where((i) => i.remainingAmount > 0).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final enteredAmount = double.tryParse(_amountController.text.trim());
    final isFullSettlement =
        enteredAmount != null && enteredAmount >= totalOutstanding - 0.005;
    InstallmentSettlementPlan? previewPlan;
    if (enteredAmount != null &&
        enteredAmount > 0 &&
        enteredAmount <= totalOutstanding) {
      previewPlan = InstallmentSettlement.plan(outstanding, enteredAmount);
    }

    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: 'Settle a lump sum',
        description:
            'Enter one amount — it settles the oldest unpaid payments first, in order.',
        confirmLabel: 'Settle payment',
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.amountUpTo(totalOutstanding),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSizes.md),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(
                Icons.calendar_today_outlined,
                size: AppSizes.iconSm,
              ),
              label: Text('${_date.day}/${_date.month}/${_date.year}'),
            ),
            const SizedBox(height: AppSizes.md),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
            if (previewPlan != null && previewPlan.portions.isNotEmpty) ...[
              const SizedBox(height: AppSizes.lg),
              if (isFullSettlement)
                _FullSettlementNotice(outstanding: totalOutstanding)
              else
                _SettlementAllocationPreview(amount: enteredAmount!, plan: previewPlan),
            ],
            const SizedBox(height: AppSizes.lg),
            PayerPicker(
              isSomeoneElse: _someoneElsePaid,
              onModeChanged: (value) => setState(() {
                _someoneElsePaid = value;
                if (!value) _selectedPersonId = null;
              }),
              selectedPersonId: _selectedPersonId,
              onPersonChanged: (value) =>
                  setState(() => _selectedPersonId = value),
            ),
            const SizedBox(height: AppSizes.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total outstanding', style: context.textTheme.titleMedium),
                Text(
                  CurrencyFormatter.instance.format(totalOutstanding),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows how a lump sum will fan out across outstanding installments
/// (oldest-due-first, per [InstallmentSettlement.plan]) before the user
/// confirms — purely derived from the plan, no repository calls.
class _SettlementAllocationPreview extends StatelessWidget {
  const _SettlementAllocationPreview({required this.amount, required this.plan});

  final double amount;
  final InstallmentSettlementPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Settlement', style: context.textTheme.titleMedium),
              Text(
                CurrencyFormatter.instance.format(amount),
                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          for (final portion in plan.portions) _AllocationRow(portion: portion),
          if (plan.unallocated > 0.005) ...[
            const SizedBox(height: 4),
            Text(
              'Unallocated: ${CurrencyFormatter.instance.format(plan.unallocated)}',
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.portion});

  final InstallmentSettlementPortion portion;

  @override
  Widget build(BuildContext context) {
    final fullyPaid = portion.portion >= portion.installment.remainingAmount - 0.005;
    final resultLabel = fullyPaid ? 'Fully Paid' : 'Partial';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('EMI #${portion.installment.sequenceNumber}', style: context.textTheme.bodyMedium),
          Text(
            '${CurrencyFormatter.instance.format(portion.portion)} → $resultLabel',
            style: context.textTheme.bodyMedium?.copyWith(
              color: fullyPaid ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the per-installment allocation breakdown when the
/// entered amount covers the loan's entire outstanding balance — closing
/// the loan (if desired) still requires the existing explicit Close action;
/// this is UI messaging only and never touches `Loan.isClosed`.
class _FullSettlementNotice extends StatelessWidget {
  const _FullSettlementNotice({required this.outstanding});

  final double outstanding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are settling this loan.',
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Outstanding', style: context.textTheme.bodyMedium),
              Text(CurrencyFormatter.instance.format(outstanding), style: context.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text('After this payment:', style: context.textTheme.bodySmall),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Outstanding', style: context.textTheme.bodyMedium),
              Text(
                CurrencyFormatter.instance.format(0),
                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
