import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/models/payer_source.dart';
import '../../../../core/payment_schedule/domain/installment_settlement.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/payment_attribution_service.dart';
import '../../../../core/services/providers/payment_attribution_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/emi.dart';
import '../providers/emi_providers.dart';

/// Bottom sheet for settling a single lump-sum amount across an EMI's
/// outstanding installments, oldest-due-first — unlike
/// [RecordEmiMultiPaymentSheet] (which pays each hand-picked installment IN
/// FULL), this sheet fans one entered amount across as many installments as
/// it covers via [InstallmentSettlement.plan], letting the last one touched
/// be only partially paid. Routed through [PaymentAttributionService.apply]
/// exactly like every other EMI payment sheet, so a Person payer still
/// posts one combined ledger entry for the whole settlement.
class RecordEmiLumpSumSettlementSheet extends ConsumerStatefulWidget {
  const RecordEmiLumpSumSettlementSheet({super.key, required this.emi});

  final Emi emi;

  static Future<void> show(BuildContext context, Emi emi) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordEmiLumpSumSettlementSheet(emi: emi),
    );
  }

  @override
  ConsumerState<RecordEmiLumpSumSettlementSheet> createState() => _RecordEmiLumpSumSettlementSheetState();
}

class _RecordEmiLumpSumSettlementSheetState extends ConsumerState<RecordEmiLumpSumSettlementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: ref.read(emiRemainingAmountProvider(widget.emi)).toStringAsFixed(2),
  );
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  bool _someoneElsePaid = false;
  String? _selectedPersonId;

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
    if (payer case PersonPayerSource(:final person)) return 'Paid by ${person.name}';
    return '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_someoneElsePaid && _selectedPersonId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose who paid')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final installments = ref.read(installmentsStreamProvider(widget.emi.scheduleId)).value ?? const [];
      final outstanding = installments.where((i) => i.remainingAmount > 0).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      final amount = double.parse(_amountController.text.trim());
      final plan = InstallmentSettlement.plan(outstanding, amount);

      final items = [
        for (final p in plan.portions)
          PaymentAttributionItem(
            obligationLabel: 'your ${widget.emi.name} (payment ${p.installment.sequenceNumber})',
            amount: p.portion,
            record: ({required amount, required date, required note}) => ref
                .read(
                  installmentPaymentRepositoryProvider(
                    (scheduleId: p.installment.scheduleId, installmentId: p.installment.id),
                  ),
                )
                .recordPayment(p.installment, amount: amount, date: date, note: note),
          ),
      ];

      final payer = _resolvePayer();
      await ref.read(paymentAttributionServiceProvider).apply(
        items: items,
        payer: payer,
        date: _date,
        note: _resolveNote(payer),
      );

      final refreshed = ref.read(installmentsStreamProvider(widget.emi.scheduleId)).value ?? const [];
      final nextUnpaid = refreshed.where((i) => i.status != InstallmentStatus.paid).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      if (nextUnpaid.isNotEmpty) {
        ref.read(emiRepositoryProvider).rescheduleReminders(widget.emi, nextUnpaid.first.dueDate);
      }

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
    final totalOutstanding = ref.watch(emiRemainingAmountProvider(widget.emi));

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
              Text('Settle a lump sum for ${widget.emi.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Enter one amount — it settles your oldest unpaid payments first, in order.',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amountUpTo(totalOutstanding),
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: AppSizes.md),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                label: Text('${_date.day}/${_date.month}/${_date.year}'),
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
              const SizedBox(height: AppSizes.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total outstanding', style: context.textTheme.titleMedium),
                  Text(
                    CurrencyFormatter.instance.format(totalOutstanding),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(label: 'Settle payment', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
