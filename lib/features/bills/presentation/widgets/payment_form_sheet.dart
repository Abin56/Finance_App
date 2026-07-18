import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/models/payer_source.dart';
import '../../../../core/services/payment_attribution_service.dart';
import '../../../../core/services/providers/payment_attribution_providers.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
import '../../domain/bill.dart';
import '../providers/bill_providers.dart';

/// Bottom sheet for recording a (possibly partial) payment against a
/// bill's current occurrence. Payments are append-only — this sheet only
/// ever creates, never edits, matching [PaymentRepository]'s API.
class PaymentFormSheet extends ConsumerStatefulWidget {
  const PaymentFormSheet({super.key, required this.bill, this.smsPrefill});

  final Bill bill;

  /// Set when opened from the SMS Inbox's "Bill Payment" option (after the
  /// user picked which bill via the bill picker) — seeds amount/date/note.
  final SmsPrefill? smsPrefill;

  static Future<void> show(BuildContext context, Bill bill, {SmsPrefill? smsPrefill}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PaymentFormSheet(bill: bill, smsPrefill: smsPrefill),
    );
  }

  @override
  ConsumerState<PaymentFormSheet> createState() => _PaymentFormSheetState();
}

class _PaymentFormSheetState extends ConsumerState<PaymentFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: (widget.smsPrefill?.amount ?? widget.bill.remainingAmount).toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(text: widget.smsPrefill?.note ?? '');
  late DateTime _date = widget.smsPrefill?.dateTime ?? DateTime.now();
  bool _isSaving = false;
  bool _someoneElsePaid = false;
  String? _selectedPersonId;

  bool get _isAmountValid => Validators.amountUpTo(widget.bill.remainingAmount)(_amountController.text) == null;

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
  /// an empty string so the payment history tile can show who paid without
  /// `PaymentRecord` needing a new field.
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
      final repository = ref.read(paymentRepositoryProvider(widget.bill.id));
      final amount = double.parse(_amountController.text.trim());
      final payer = _resolvePayer();

      await ref.read(paymentAttributionServiceProvider).apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your ${widget.bill.name} bill',
            amount: amount,
            record: ({required amount, required date, required note}) => repository.recordPayment(
              widget.bill,
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

      await completeSmsImport(ref, smsPrefill: widget.smsPrefill, linkedEntityId: widget.bill.id);
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
              Text('Record payment for ${widget.bill.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amountUpTo(widget.bill.remainingAmount),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                label: Text(_date.fullDate),
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
