import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/models/payer_source.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/payment_attribution_service.dart';
import '../../../../core/services/providers/payment_attribution_providers.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';

/// Bottom sheet for recording a payment against a loan installment.
/// Supports partial payments (amount less than what's remaining) and
/// early/advance payments (any date) with no special handling — any
/// positive amount and date is accepted.
class RecordLoanPaymentSheet extends ConsumerStatefulWidget {
  const RecordLoanPaymentSheet({super.key, required this.installment, this.smsPrefill});

  final Installment installment;

  /// Set when opened from the SMS Inbox's "Loan Payment" option (after the
  /// user picked which loan/installment via the obligation picker) — seeds
  /// amount/date/note instead of the installment's full remaining amount/now.
  final SmsPrefill? smsPrefill;

  static Future<void> show(BuildContext context, Installment installment, {SmsPrefill? smsPrefill}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordLoanPaymentSheet(installment: installment, smsPrefill: smsPrefill),
    );
  }

  @override
  ConsumerState<RecordLoanPaymentSheet> createState() => _RecordLoanPaymentSheetState();
}

class _RecordLoanPaymentSheetState extends ConsumerState<RecordLoanPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: (widget.smsPrefill?.amount ?? widget.installment.remainingAmount).toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(text: widget.smsPrefill?.note ?? '');
  late DateTime _date = widget.smsPrefill?.dateTime ?? DateTime.now();
  bool _isSaving = false;
  bool _someoneElsePaid = false;
  String? _selectedPersonId;

  bool get _isAmountValid => Validators.amountUpTo(widget.installment.remainingAmount)(_amountController.text) == null;

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
    if (payer case PersonPayerSource(:final person)) return 'Paid by ${person.name}';
    return '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(
        installmentPaymentRepositoryProvider(
          (scheduleId: widget.installment.scheduleId, installmentId: widget.installment.id),
        ),
      );
      final amount = double.parse(_amountController.text.trim());
      final payer = _resolvePayer();

      await ref.read(paymentAttributionServiceProvider).apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your loan payment',
            amount: amount,
            record: ({required amount, required date, required note}) => repository.recordPayment(
              widget.installment,
              amount: amount,
              date: date,
              note: note,
            ),
          ),
        ],
        payer: payer,
        date: _date,
        note: _resolveNote(payer),
      );

      await completeSmsImport(
        ref,
        smsPrefill: widget.smsPrefill,
        linkedEntityId: '${widget.installment.scheduleId}:${widget.installment.id}',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record payment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record payment', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amountUpTo(widget.installment.remainingAmount),
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
              const SizedBox(height: AppSizes.lg),
              PayerPicker(
                isSomeoneElse: _someoneElsePaid,
                onModeChanged: (value) => setState(() {
                  _someoneElsePaid = value;
                  if (!value) _selectedPersonId = null;
                }),
                selectedPersonId: _selectedPersonId,
                onPersonChanged: (value) => setState(() => _selectedPersonId = value),
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: 'Record payment',
                isLoading: _isSaving,
                onPressed: _isAmountValid ? _save : null,
              ),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
