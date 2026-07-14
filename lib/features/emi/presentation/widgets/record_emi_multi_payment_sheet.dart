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
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/emi.dart';
import '../providers/emi_providers.dart';

/// Bottom sheet for recording one payment against 2+ unpaid installments of
/// the same EMI at once — "a friend paid several EMIs together" — routed
/// through `PaymentAttributionService.apply` as a single batch so it posts
/// one combined ledger line instead of one per installment. Each selected
/// installment is paid in full for its own remaining amount; no partial
/// amount entry here (use the single-installment sheet for that).
class RecordEmiMultiPaymentSheet extends ConsumerStatefulWidget {
  const RecordEmiMultiPaymentSheet({super.key, required this.emi, required this.installments});

  final Emi emi;

  /// Candidate installments to choose from — callers should pass only
  /// unpaid/partially paid ones.
  final List<Installment> installments;

  static Future<void> show(BuildContext context, Emi emi, List<Installment> installments) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordEmiMultiPaymentSheet(emi: emi, installments: installments),
    );
  }

  @override
  ConsumerState<RecordEmiMultiPaymentSheet> createState() => _RecordEmiMultiPaymentSheetState();
}

class _RecordEmiMultiPaymentSheetState extends ConsumerState<RecordEmiMultiPaymentSheet> {
  final Set<String> _selectedIds = {};
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  bool _someoneElsePaid = false;
  String? _selectedPersonId;

  double get _total => widget.installments
      .where((i) => _selectedIds.contains(i.id))
      .fold(0.0, (sum, i) => sum + i.remainingAmount);

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

  /// The note stored on every payment in this batch — "Paid by `<name>`" when
  /// someone else paid, since there's no free-text note field in this
  /// sheet (each installment already carries its own label).
  String _noteFor(PayerSource payer) {
    if (payer case PersonPayerSource(:final person)) return 'Paid by ${person.name}';
    return '';
  }

  Future<void> _save() async {
    if (_selectedIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least 2 payments to pay together')),
      );
      return;
    }
    if (_someoneElsePaid && _selectedPersonId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose who paid')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final selected = widget.installments.where((i) => _selectedIds.contains(i.id)).toList();

      final items = [
        for (final installment in selected)
          PaymentAttributionItem(
            obligationLabel: 'your ${widget.emi.name} (payment ${installment.sequenceNumber})',
            amount: installment.remainingAmount,
            record: ({required amount, required date, required note}) => ref
                .read(
                  installmentPaymentRepositoryProvider(
                    (scheduleId: installment.scheduleId, installmentId: installment.id),
                  ),
                )
                .recordPayment(installment, amount: amount, date: date, note: note),
          ),
      ];

      final payer = _resolvePayer();
      await ref.read(paymentAttributionServiceProvider).apply(
        items: items,
        payer: payer,
        date: _date,
        note: _noteFor(payer),
      );

      final installments = ref.read(installmentsStreamProvider(widget.emi.scheduleId)).value ?? const [];
      final nextUnpaid = installments.where((i) => i.status != InstallmentStatus.paid).toList()
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
    final sorted = [...widget.installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pay multiple payments together', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSizes.sm),
            Text(
              'Choose 2 or more payments to record as one payment.',
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: AppSizes.md),
            for (final installment in sorted)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selectedIds.contains(installment.id),
                title: Text('Payment ${installment.sequenceNumber}'),
                subtitle: Text(CurrencyFormatter.instance.format(installment.remainingAmount)),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selectedIds.add(installment.id);
                  } else {
                    _selectedIds.remove(installment.id);
                  }
                }),
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
                Text('Total', style: context.textTheme.titleMedium),
                Text(
                  CurrencyFormatter.instance.format(_total),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(label: 'Record payment', isLoading: _isSaving, onPressed: _save),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }
}
