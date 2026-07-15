import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/models/payer_source.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/payment_attribution_service.dart';
import '../../../../core/services/providers/payment_attribution_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/payer_picker.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../../domain/emi.dart';
import '../providers/emi_providers.dart';

/// Bottom sheet for recording a payment against an EMI installment.
/// Supports partial payments and early/advance payments with no special
/// handling, same as Lending's equivalent sheet. Principal Paid and
/// Interest Paid are entered explicitly (pre-filled from the installment's
/// theoretical split) rather than derived, since a real bank statement's
/// actual split can differ from the amortization schedule's theoretical
/// one; the optional charge fields below (GST, IGST, etc.) are tracked for
/// the user's records only and never affect the installment's amountDue —
/// see `EmiPaymentBreakdown`. Additionally reschedules the EMI's reminders
/// after a successful payment, since EMI's "next unpaid installment"
/// changes with every payment (unlike Bills/Loans, which only reschedule on
/// create/edit).
class RecordEmiPaymentSheet extends ConsumerStatefulWidget {
  const RecordEmiPaymentSheet({super.key, required this.emi, required this.installment, this.smsPrefill});

  final Emi emi;
  final Installment installment;

  /// Set when opened from the SMS Inbox's "EMI Payment" option — seeds the
  /// principal field with the full SMS amount and the date/note, since bank
  /// SMS never break a payment into principal/interest; interest stays at
  /// its theoretical default and remains user-editable either way.
  final SmsPrefill? smsPrefill;

  static Future<void> show(BuildContext context, Emi emi, Installment installment, {SmsPrefill? smsPrefill}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordEmiPaymentSheet(emi: emi, installment: installment, smsPrefill: smsPrefill),
    );
  }

  @override
  ConsumerState<RecordEmiPaymentSheet> createState() => _RecordEmiPaymentSheetState();
}

class _RecordEmiPaymentSheetState extends ConsumerState<RecordEmiPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _principalController = TextEditingController(
    text: (widget.smsPrefill?.amount ?? _defaultPrincipal).toStringAsFixed(2),
  );
  late final _interestController = TextEditingController(text: _defaultInterest.toStringAsFixed(2));
  final _gstController = TextEditingController();
  final _igstController = TextEditingController();
  final _processingFeeController = TextEditingController();
  final _insuranceChargeController = TextEditingController();
  final _serviceChargeController = TextEditingController();
  final _penaltyController = TextEditingController();
  final _otherChargesController = TextEditingController();
  late final _noteController = TextEditingController(text: widget.smsPrefill?.note ?? '');
  late DateTime _date = widget.smsPrefill?.dateTime ?? DateTime.now();
  bool _isSaving = false;
  bool _someoneElsePaid = false;
  String? _selectedPersonId;
  bool _showCharges = false;

  /// Proportional split of the installment's *remaining* amount using its
  /// theoretical principal/interest portions — a sensible starting point
  /// the user can override with the real figures from their bank statement.
  double get _defaultPrincipal {
    final principalPortion = widget.installment.principalPortion;
    if (principalPortion == null) return widget.installment.remainingAmount;
    final remaining = widget.installment.remainingAmount;
    final due = widget.installment.amountDue;
    if (due == 0) return remaining;
    return (remaining * (principalPortion / due)).clamp(0, remaining).toDouble();
  }

  double get _defaultInterest {
    final interestPortion = widget.installment.interestPortion;
    if (interestPortion == null) return 0;
    final due = widget.installment.amountDue;
    final remaining = widget.installment.remainingAmount;
    if (due == 0) return 0;
    return (remaining * (interestPortion / due)).clamp(0, remaining).toDouble();
  }

  @override
  void dispose() {
    _principalController.dispose();
    _interestController.dispose();
    _gstController.dispose();
    _igstController.dispose();
    _processingFeeController.dispose();
    _insuranceChargeController.dispose();
    _serviceChargeController.dispose();
    _penaltyController.dispose();
    _otherChargesController.dispose();
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

  double _parsed(TextEditingController controller) => double.tryParse(controller.text.trim()) ?? 0;

  double get _totalAmountPaid =>
      _parsed(_principalController) +
      _parsed(_interestController) +
      _parsed(_gstController) +
      _parsed(_igstController) +
      _parsed(_processingFeeController) +
      _parsed(_insuranceChargeController) +
      _parsed(_serviceChargeController) +
      _parsed(_penaltyController) +
      _parsed(_otherChargesController);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final paymentRepository = ref.read(
        installmentPaymentRepositoryProvider(
          (scheduleId: widget.installment.scheduleId, installmentId: widget.installment.id),
        ),
      );
      final principalPaid = _parsed(_principalController);
      final interestPaid = _parsed(_interestController);
      final gst = _parsed(_gstController);
      final igst = _parsed(_igstController);
      final processingFee = _parsed(_processingFeeController);
      final insuranceCharge = _parsed(_insuranceChargeController);
      final serviceCharge = _parsed(_serviceChargeController);
      final penalty = _parsed(_penaltyController);
      final otherCharges = _parsed(_otherChargesController);
      final notes = _noteController.text.trim();

      // Only principal + interest actually pay down the installment —
      // charges/fees are tracked for the user's records but never reduce
      // amountDue (matching the same "charges don't touch the real
      // balance" rule applied to credit-card restoration).
      final installmentAmount = principalPaid + interestPaid;
      final payer = _resolvePayer();

      await ref.read(paymentAttributionServiceProvider).apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your ${widget.emi.name}',
            amount: installmentAmount,
            record: ({required amount, required date, required note}) async {
              final payment = await paymentRepository.recordPayment(
                widget.installment,
                amount: amount,
                date: date,
                note: note,
              );
              await ref.read(emiPaymentBreakdownRepositoryProvider(widget.emi.id)).createBreakdown(
                    paymentId: payment.id,
                    scheduleId: widget.installment.scheduleId,
                    installmentId: widget.installment.id,
                    principalPaid: principalPaid,
                    interestPaid: interestPaid,
                    gst: gst,
                    igst: igst,
                    processingFee: processingFee,
                    insuranceCharge: insuranceCharge,
                    serviceCharge: serviceCharge,
                    penalty: penalty,
                    otherCharges: otherCharges,
                    notes: notes,
                  );
            },
          ),
        ],
        payer: payer,
        date: _date,
        note: _resolveNote(payer),
      );

      final installments = ref.read(installmentsStreamProvider(widget.emi.scheduleId)).value ?? const [];
      final nextUnpaid = installments.where((i) => i.status != InstallmentStatus.paid).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      if (nextUnpaid.isNotEmpty) {
        ref.read(emiRepositoryProvider).rescheduleReminders(widget.emi, nextUnpaid.first.dueDate);
      }

      final smsPrefill = widget.smsPrefill;
      if (smsPrefill != null) {
        await ref.read(smsInboxItemsProvider.notifier).markImported(
              smsPrefill.smsId,
              linkedEntityId: '${widget.installment.scheduleId}:${widget.installment.id}',
            );
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
                controller: _principalController,
                decoration: const InputDecoration(labelText: 'Principal paid'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _interestController,
                decoration: const InputDecoration(labelText: 'Interest paid'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              const SizedBox(height: AppSizes.sm),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: const Text('GST, fees & other charges (optional)'),
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: _showCharges,
                  onExpansionChanged: (expanded) => setState(() => _showCharges = expanded),
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    TextFormField(
                      controller: _gstController,
                      decoration: const InputDecoration(labelText: 'GST'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _igstController,
                      decoration: const InputDecoration(labelText: 'IGST'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _processingFeeController,
                      decoration: const InputDecoration(labelText: 'Processing fee'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _insuranceChargeController,
                      decoration: const InputDecoration(labelText: 'Insurance charge'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _serviceChargeController,
                      decoration: const InputDecoration(labelText: 'Service charge'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _penaltyController,
                      decoration: const InputDecoration(labelText: 'Penalty'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _otherChargesController,
                      decoration: const InputDecoration(labelText: 'Other charges'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),
              Container(
                padding: const EdgeInsets.all(AppSizes.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Text(
                  'Total amount paid: ${CurrencyFormatter.instance.format(_totalAmountPaid)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
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
              PrimaryButton(label: 'Record payment', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
