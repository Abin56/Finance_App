import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/models/payer_source.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/payment_attribution_service.dart';
import '../../../../core/services/providers/payment_attribution_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
import '../../domain/loan.dart';
import '../providers/loan_providers.dart';

/// Bottom sheet for recording a payment against a loan installment.
/// Supports partial payments (amount less than what's remaining) and
/// early/advance payments (any date) with no special handling — any
/// positive amount and date is accepted.
class RecordLoanPaymentSheet extends ConsumerStatefulWidget {
  const RecordLoanPaymentSheet({
    super.key,
    required this.installment,
    this.loan,
    this.smsPrefill,
  });

  final Installment installment;

  /// The loan this installment belongs to, when the caller has it on hand —
  /// used only to default "Who Paid" to [Loan.payerPersonId] when set (the
  /// person who actually pays this loan's EMIs). Optional since the SMS
  /// Inbox conversion flow doesn't resolve a `Loan` object today; that path
  /// simply falls back to the "I pay it myself" default, unchanged.
  final Loan? loan;

  /// Set when opened from the SMS Inbox's "Loan Payment" option (after the
  /// user picked which loan/installment via the obligation picker) — seeds
  /// amount/date/note instead of the installment's full remaining amount/now.
  final SmsPrefill? smsPrefill;

  static Future<void> show(
    BuildContext context,
    Installment installment, {
    Loan? loan,
    SmsPrefill? smsPrefill,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => RecordLoanPaymentSheet(
        installment: installment,
        loan: loan,
        smsPrefill: smsPrefill,
      ),
    );
  }

  @override
  ConsumerState<RecordLoanPaymentSheet> createState() =>
      _RecordLoanPaymentSheetState();
}

class _RecordLoanPaymentSheetState
    extends ConsumerState<RecordLoanPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: (widget.smsPrefill?.amount ?? widget.installment.remainingAmount)
        .toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(
    text: widget.smsPrefill?.note ?? '',
  );
  late DateTime _date = widget.smsPrefill?.dateTime ?? DateTime.now();
  bool _isSaving = false;
  late bool _someoneElsePaid = widget.loan?.payerPersonId != null;
  late String? _selectedPersonId = widget.loan?.payerPersonId;

  bool get _isAmountValid =>
      Validators.amountUpTo(widget.installment.remainingAmount)(
        _amountController.text,
      ) ==
      null;

  double? get _enteredAmount => double.tryParse(_amountController.text.trim());

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

  /// The note actually stored on the payment record. If the user left the
  /// note blank and someone else paid, records "Paid by `<name>`" instead of
  /// an empty string so payment history can show who paid without
  /// `InstallmentPayment` needing a new field.
  String _resolveNote(PayerSource payer) {
    final typed = _noteController.text.trim();
    if (typed.isNotEmpty) return typed;
    if (payer case PersonPayerSource(:final person))
      return 'Paid by ${person.name}';
    return '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(
        installmentPaymentRepositoryProvider((
          scheduleId: widget.installment.scheduleId,
          installmentId: widget.installment.id,
        )),
      );
      final amount = double.parse(_amountController.text.trim());
      final payer = _resolvePayer();

      await ref
          .read(paymentAttributionServiceProvider)
          .apply(
            items: [
              PaymentAttributionItem(
                obligationLabel: 'your loan payment',
                amount: amount,
                record: ({required amount, required date, required note}) =>
                    repository.recordPayment(
                      widget.installment,
                      amount: amount,
                      date: date,
                      note: note,
                      payerPersonId: switch (payer) {
                        PersonPayerSource(:final person) => person.id,
                        SelfPayerSource() => null,
                      },
                    ),
              ),
            ],
            payer: payer,
            date: _date,
            note: _resolveNote(payer),
          );

      if (widget.loan != null) {
        final installments = ref.read(installmentsStreamProvider(widget.installment.scheduleId)).value ?? const [];
        final nextUnpaid = installments.where((i) => i.remainingAmount > 0 && !i.isSkipped).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final repository = ref.read(loanRepositoryProvider);
        if (nextUnpaid.isNotEmpty) {
          repository.rescheduleReminders(widget.loan!, nextUnpaid.first.dueDate);
        } else {
          repository.cancelReminders(widget.loan!.id);
        }
      }

      await completeSmsImport(
        ref,
        smsPrefill: widget.smsPrefill,
        linkedEntityId:
            '${widget.installment.scheduleId}:${widget.installment.id}',
      );
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
    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: 'Record payment',
        confirmLabel: 'Record payment',
        isSaving: _isSaving,
        confirmEnabled: _isAmountValid,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Installment'),
            const SizedBox(height: AppSizes.sm),
            Text('EMI #${widget.installment.sequenceNumber}', style: context.textTheme.titleMedium),
            const SizedBox(height: AppSizes.sm),
            _SummaryRow(label: 'Amount Due', value: widget.installment.amountDue),
            _SummaryRow(label: 'Already Paid', value: widget.installment.amountPaid),
            _SummaryRow(label: 'Remaining', value: widget.installment.remainingAmount, emphasize: true),
            const SizedBox(height: AppSizes.lg),
            const SectionLabel('Payment Details'),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.amountUpTo(
                widget.installment.remainingAmount,
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSizes.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: AppSizes.md),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
            if (_isAmountValid && _enteredAmount != null) ...[
              const SizedBox(height: AppSizes.lg),
              const SectionLabel('Payment Preview'),
              const SizedBox(height: AppSizes.sm),
              _PaymentPreview(installment: widget.installment, amount: _enteredAmount!),
            ],
            const SizedBox(height: AppSizes.lg),
            const SectionLabel('Who Paid'),
            const SizedBox(height: AppSizes.sm),
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
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : context.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(CurrencyFormatter.instance.format(value), style: style),
        ],
      ),
    );
  }
}

/// Shows the installment's remaining balance before/after the entered
/// amount, and the resulting [InstallmentStatus] label — purely derived from
/// [installment] and [amount], no repository calls.
class _PaymentPreview extends StatelessWidget {
  const _PaymentPreview({required this.installment, required this.amount});

  final Installment installment;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final remainingBefore = installment.remainingAmount;
    final remainingAfter = (remainingBefore - amount).clamp(0, installment.amountDue);
    final statusAfter = remainingAfter <= 0 ? InstallmentStatus.paid : InstallmentStatus.partiallyPaid;

    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(label: 'Payment', value: amount, emphasize: true),
          _SummaryRow(label: 'Installment remaining before', value: remainingBefore),
          _SummaryRow(label: 'Remaining after', value: remainingAfter.toDouble()),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Status after payment', style: context.textTheme.bodyMedium),
              Text(
                statusAfter.label,
                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: statusAfter.color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
