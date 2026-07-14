import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/interest/interest_calculator.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/emi.dart';
import '../../domain/emi_interest.dart';
import '../../domain/emi_loan_type.dart';
import '../providers/emi_providers.dart';

/// Bottom sheet for creating or editing an EMI. Frequency, number of
/// payments, interest terms, and the Monthly Due Date can all be changed
/// even after payments exist (via `EmiRepository.editEmiTerms`) —
/// already-paid/partially-paid installments are left untouched, and only
/// the unpaid tail of the schedule is regenerated against the outstanding
/// principal and new terms. First EMI Date ([startDate]) stays locked (it
/// only ever seeded the very first installment, which never moves even
/// when the Monthly Due Date changes). EMI always repays via installments
/// (there's no one-time mode, unlike Loan).
class EmiFormSheet extends ConsumerStatefulWidget {
  const EmiFormSheet({super.key, this.emi});

  final Emi? emi;

  static Future<void> show(BuildContext context, {Emi? emi}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => EmiFormSheet(emi: emi),
    );
  }

  @override
  ConsumerState<EmiFormSheet> createState() => _EmiFormSheetState();
}

class _EmiFormSheetState extends ConsumerState<EmiFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.emi?.name ?? '');
  late final _lenderController = TextEditingController(text: widget.emi?.lenderName ?? '');
  late final _amountController = TextEditingController(
    text: widget.emi == null ? '' : widget.emi!.principalAmount.toStringAsFixed(2),
  );
  late final _notesController = TextEditingController(text: widget.emi?.notes ?? '');
  late final _installmentCountController = TextEditingController(
    text: widget.emi?.installmentCount.toString() ?? '',
  );
  late final _rateController = TextEditingController(
    text: widget.emi?.interest?.ratePercent.toString() ?? '',
  );
  late final _loanNumberController = TextEditingController(text: widget.emi?.loanNumber ?? '');
  late final _branchController = TextEditingController(text: widget.emi?.branch ?? '');
  late final _customerIdController = TextEditingController(text: widget.emi?.customerId ?? '');
  late final _processingFeeController = TextEditingController(
    text: widget.emi == null || widget.emi!.processingFee == 0 ? '' : widget.emi!.processingFee.toStringAsFixed(2),
  );
  late final _insuranceController = TextEditingController(
    text: widget.emi == null || widget.emi!.insuranceAmount == 0
        ? ''
        : widget.emi!.insuranceAmount.toStringAsFixed(2),
  );
  late final _extraChargesController = TextEditingController(
    text: widget.emi == null || widget.emi!.extraCharges == 0 ? '' : widget.emi!.extraCharges.toStringAsFixed(2),
  );
  late final _foreclosureController = TextEditingController(
    text: widget.emi?.foreclosureAmount?.toStringAsFixed(2) ?? '',
  );
  late final _prepaymentChargesController = TextEditingController(
    text: widget.emi?.prepaymentCharges?.toStringAsFixed(2) ?? '',
  );
  late final _autoDebitAccountController = TextEditingController(text: widget.emi?.autoDebitAccount ?? '');
  late final _dueDayOfMonthController = TextEditingController(
    text: widget.emi?.dueDayOfMonth?.toString() ?? '',
  );

  late String? _categoryId = widget.emi?.categoryId;
  late DateTime _startDate = widget.emi?.startDate ?? DateTime.now();
  late ScheduleType _installmentFrequency = widget.emi?.installmentFrequency ?? ScheduleType.monthly;
  late bool _hasInterest = widget.emi?.interest != null;
  // Real bank loans (home/personal/vehicle/etc.) are almost always quoted
  // as an annual reducing-balance rate — defaulting to that (rather than
  // flat/per-month) avoids a silent unit mismatch where a user types an
  // annual-style rate (e.g. "15.12") without noticing the toggles, producing
  // a nonsensical multi-times-the-principal preview.
  late InterestType _interestType = widget.emi?.interest?.type ?? InterestType.reducingBalance;
  late InterestPeriod _interestPeriod = widget.emi?.interest?.period ?? InterestPeriod.yearly;
  late EmiLoanType _loanType = widget.emi?.loanType ?? EmiLoanType.other;
  late String? _linkedCreditCardId = widget.emi?.linkedCreditCardId;
  DateTime? _sanctionDate;
  DateTime? _disbursementDate;
  late bool _isAutoDebitEnabled = widget.emi?.isAutoDebitEnabled ?? false;
  bool _isSaving = false;
  bool _showBankDetails = false;
  bool _showCharges = false;

  bool get _isEditing => widget.emi != null;

  @override
  void initState() {
    super.initState();
    _sanctionDate = widget.emi?.sanctionDate;
    _disbursementDate = widget.emi?.disbursementDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lenderController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _installmentCountController.dispose();
    _rateController.dispose();
    _loanNumberController.dispose();
    _branchController.dispose();
    _customerIdController.dispose();
    _processingFeeController.dispose();
    _insuranceController.dispose();
    _extraChargesController.dispose();
    _foreclosureController.dispose();
    _prepaymentChargesController.dispose();
    _autoDebitAccountController.dispose();
    _dueDayOfMonthController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickSanctionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _sanctionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _sanctionDate = picked);
  }

  Future<void> _pickDisbursementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _disbursementDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _disbursementDate = picked);
  }

  double? _parseOptionalAmount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  /// Live-computed preview — pure math, cheap to call on every rebuild.
  /// Returns null when inputs aren't complete/valid yet, so the summary
  /// section simply hides instead of surfacing a calculator exception.
  ({double totalPayable, double totalInterest})? get _preview {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return null;
    if (!_hasInterest) return null;
    final rate = double.tryParse(_rateController.text.trim());
    if (rate == null || rate < 0) return null;
    final count = int.tryParse(_installmentCountController.text.trim());
    if (count == null || count < 1) return null;

    try {
      final breakdown = InterestCalculator.calculate(
        principal: amount,
        type: _interestType,
        ratePercent: rate,
        period: _interestPeriod,
        installmentCount: count,
        installmentFrequency: InterestPeriod.monthly,
      );
      return (totalPayable: breakdown.totalPayable, totalInterest: breakdown.totalInterest);
    } catch (_) {
      return null;
    }
  }

  /// Whether the term-driving fields (interest, frequency, count) differ
  /// from what [widget.emi] currently has — used to decide whether a
  /// confirmation dialog and `editEmiTerms` call are needed at all.
  bool get _termsChanged {
    final emi = widget.emi;
    if (emi == null) return false;
    final newCount = int.tryParse(_installmentCountController.text.trim());
    if (newCount == null || newCount != emi.installmentCount) return true;
    if (_installmentFrequency != emi.installmentFrequency) return true;
    final hadInterest = emi.interest != null;
    if (_hasInterest != hadInterest) return true;
    if (_hasInterest) {
      final newRate = double.tryParse(_rateController.text.trim());
      if (newRate != emi.interest!.ratePercent) return true;
      if (_interestType != emi.interest!.type) return true;
      if (_interestPeriod != emi.interest!.period) return true;
    }
    if (_parsedDueDayOfMonth != emi.dueDayOfMonth) return true;
    return false;
  }

  int? get _parsedDueDayOfMonth => int.tryParse(_dueDayOfMonthController.text.trim());

  Future<bool> _confirmTermsChange(double remaining) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update loan terms?'),
        content: Text(
          'This recalculates your remaining ${CurrencyFormatter.instance.format(remaining)} balance over the new '
          'terms. Payments you\'ve already made won\'t change.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Update')),
        ],
      ),
    ).then((value) => value ?? false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isEditing && _termsChanged) {
      final emi = widget.emi!;
      final remaining = ref.read(emiRemainingAmountProvider(emi));
      final confirmed = await _confirmTermsChange(remaining);
      if (!confirmed) return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(emiRepositoryProvider);
      if (_isEditing) {
        final emi = widget.emi!;
        final hasPayments = ref.read(emiTotalPaidProvider(emi)) > 0;
        await repository.editEmi(
          emi,
          hasPayments: hasPayments,
          name: _nameController.text.trim(),
          lenderName: _lenderController.text.trim().isEmpty ? null : _lenderController.text.trim(),
          categoryId: _categoryId,
          principalAmount: double.parse(_amountController.text.trim()),
          notes: _notesController.text.trim(),
          loanNumber: _loanNumberController.text.trim().isEmpty ? null : _loanNumberController.text.trim(),
          loanType: _loanType,
          branch: _branchController.text.trim().isEmpty ? null : _branchController.text.trim(),
          customerId: _customerIdController.text.trim().isEmpty ? null : _customerIdController.text.trim(),
          sanctionDate: _sanctionDate,
          disbursementDate: _disbursementDate,
          processingFee: _parseOptionalAmount(_processingFeeController.text) ?? 0,
          insuranceAmount: _parseOptionalAmount(_insuranceController.text) ?? 0,
          extraCharges: _parseOptionalAmount(_extraChargesController.text) ?? 0,
          foreclosureAmount: _parseOptionalAmount(_foreclosureController.text),
          prepaymentCharges: _parseOptionalAmount(_prepaymentChargesController.text),
          isAutoDebitEnabled: _isAutoDebitEnabled,
          autoDebitAccount: _isAutoDebitEnabled && _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
          linkedCreditCardId: _linkedCreditCardId,
          clearLinkedCreditCardId: _linkedCreditCardId == null,
        );
        if (_termsChanged) {
          final installments = ref.read(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
          await repository.editEmiTerms(
            emi,
            currentInstallments: installments,
            interest: _hasInterest
                ? EmiInterest(
                    type: _interestType,
                    ratePercent: double.parse(_rateController.text.trim()),
                    period: _interestPeriod,
                  )
                : null,
            installmentFrequency: _installmentFrequency,
            newInstallmentCount: int.parse(_installmentCountController.text.trim()),
            dueDayOfMonth: _parsedDueDayOfMonth,
          );
        }
      } else {
        await repository.createEmi(
          name: _nameController.text.trim(),
          principalAmount: double.parse(_amountController.text.trim()),
          startDate: _startDate,
          installmentFrequency: _installmentFrequency,
          installmentCount: int.parse(_installmentCountController.text.trim()),
          lenderName: _lenderController.text.trim().isEmpty ? null : _lenderController.text.trim(),
          categoryId: _categoryId,
          interest: _hasInterest
              ? EmiInterest(
                  type: _interestType,
                  ratePercent: double.parse(_rateController.text.trim()),
                  period: _interestPeriod,
                )
              : null,
          notes: _notesController.text.trim(),
          loanNumber: _loanNumberController.text.trim().isEmpty ? null : _loanNumberController.text.trim(),
          loanType: _loanType,
          branch: _branchController.text.trim().isEmpty ? null : _branchController.text.trim(),
          customerId: _customerIdController.text.trim().isEmpty ? null : _customerIdController.text.trim(),
          sanctionDate: _sanctionDate,
          disbursementDate: _disbursementDate,
          processingFee: _parseOptionalAmount(_processingFeeController.text) ?? 0,
          insuranceAmount: _parseOptionalAmount(_insuranceController.text) ?? 0,
          extraCharges: _parseOptionalAmount(_extraChargesController.text) ?? 0,
          foreclosureAmount: _parseOptionalAmount(_foreclosureController.text),
          prepaymentCharges: _parseOptionalAmount(_prepaymentChargesController.text),
          isAutoDebitEnabled: _isAutoDebitEnabled,
          autoDebitAccount: _isAutoDebitEnabled && _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
          linkedCreditCardId: _linkedCreditCardId,
          dueDayOfMonth: _parsedDueDayOfMonth,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save EMI: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(activeCategoriesProvider);
    final preview = _preview;
    final hasPayments = _isEditing ? ref.watch(emiTotalPaidProvider(widget.emi!)) > 0 : false;
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final accountNameById = {for (final a in accounts) a.id: a.name};

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
              Text(_isEditing ? 'Edit EMI' : 'Add EMI', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Loan name'),
                validator: Validators.required,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _lenderController,
                decoration: const InputDecoration(labelText: 'Bank / finance company (optional)'),
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<EmiLoanType>(
                initialValue: _loanType,
                decoration: const InputDecoration(labelText: 'Loan type'),
                items: [
                  for (final type in EmiLoanType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) => setState(() => _loanType = value ?? EmiLoanType.other),
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String?>(
                initialValue: _linkedCreditCardId,
                decoration: const InputDecoration(
                  labelText: 'Linked credit card (optional)',
                  helperText: 'If this loan came from a card purchase converted to EMI',
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('None')),
                  for (final card in creditCards)
                    DropdownMenuItem<String?>(
                      value: card.id,
                      child: Text(accountNameById[card.accountId] ?? 'Card'),
                    ),
                ],
                onChanged: (value) => setState(() => _linkedCreditCardId = value),
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category (optional)'),
                items: [
                  for (final category in categories) DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _amountController,
                enabled: !hasPayments,
                decoration: InputDecoration(
                  labelText: 'Loan amount',
                  helperText: hasPayments ? 'Amount can\'t be changed after a payment has been recorded' : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !_isEditing,
                title: const Text('First EMI Date'),
                subtitle: Text('${_startDate.day}/${_startDate.month}/${_startDate.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _isEditing ? null : _pickStartDate,
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<ScheduleType>(
                initialValue: _installmentFrequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: const [
                  DropdownMenuItem(value: ScheduleType.weekly, child: Text('Weekly')),
                  DropdownMenuItem(value: ScheduleType.monthly, child: Text('Monthly')),
                ],
                onChanged: (value) => setState(() => _installmentFrequency = value ?? ScheduleType.monthly),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _installmentCountController,
                decoration: InputDecoration(
                  labelText: 'Number of payments',
                  helperText:
                      _isEditing ? 'Can\'t be less than the number of payments already made' : null,
                ),
                keyboardType: TextInputType.number,
                validator: Validators.required,
                onChanged: (_) => setState(() {}),
              ),
              if (_installmentFrequency == ScheduleType.monthly) ...[
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: _dueDayOfMonthController,
                  decoration: const InputDecoration(
                    labelText: 'Monthly due date (optional)',
                    helperText: 'The fixed day every EMI after the first is due on, e.g. 5 for the 5th',
                    suffixText: 'day of month',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return null;
                    final day = int.tryParse(trimmed);
                    if (day == null || day < 1 || day > 31) return 'Enter a day between 1 and 31';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add interest'),
                value: _hasInterest,
                onChanged: (value) => setState(() => _hasInterest = value),
              ),
              if (_hasInterest) ...[
                SegmentedButton<InterestType>(
                  segments: const [
                    ButtonSegment(value: InterestType.flat, label: Text('Flat')),
                    ButtonSegment(value: InterestType.reducingBalance, label: Text('Reducing balance')),
                  ],
                  selected: {_interestType},
                  onSelectionChanged: (selection) => setState(() => _interestType = selection.first),
                ),
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: _rateController,
                  decoration: InputDecoration(
                    labelText: 'Interest rate (%)',
                    helperText: _interestPeriod == InterestPeriod.yearly
                        ? 'Enter the yearly rate (e.g. a bank\'s quoted rate, like 15.12)'
                        : 'Enter the rate charged per month',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSizes.md),
                SegmentedButton<InterestPeriod>(
                  segments: const [
                    ButtonSegment(value: InterestPeriod.monthly, label: Text('Per month')),
                    ButtonSegment(value: InterestPeriod.yearly, label: Text('Per year')),
                  ],
                  selected: {_interestPeriod},
                  onSelectionChanged: (selection) => setState(() => _interestPeriod = selection.first),
                ),
                if (preview != null) ...[
                  const SizedBox(height: AppSizes.md),
                  Container(
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total to pay: ${CurrencyFormatter.instance.format(preview.totalPayable)}'),
                        Text('Total interest: ${CurrencyFormatter.instance.format(preview.totalInterest)}'),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSizes.md),
              ExpansionTile(
                title: const Text('Bank details (optional)'),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _showBankDetails,
                onExpansionChanged: (expanded) => setState(() => _showBankDetails = expanded),
                childrenPadding: EdgeInsets.zero,
                children: [
                  TextFormField(
                    controller: _loanNumberController,
                    decoration: const InputDecoration(labelText: 'Loan / account number'),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _branchController,
                    decoration: const InputDecoration(labelText: 'Branch'),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _customerIdController,
                    decoration: const InputDecoration(labelText: 'Customer ID'),
                  ),
                  const SizedBox(height: AppSizes.md),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sanction date'),
                    subtitle: Text(
                      _sanctionDate == null
                          ? 'Not set'
                          : '${_sanctionDate!.day}/${_sanctionDate!.month}/${_sanctionDate!.year}',
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: _pickSanctionDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Loan Disbursement Date'),
                    subtitle: Text(
                      _disbursementDate == null
                          ? 'Not set'
                          : '${_disbursementDate!.day}/${_disbursementDate!.month}/${_disbursementDate!.year}',
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: _pickDisbursementDate,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto debit enabled'),
                    subtitle: const Text('For your reference only — this app does not process payments'),
                    value: _isAutoDebitEnabled,
                    onChanged: (value) => setState(() => _isAutoDebitEnabled = value),
                  ),
                  if (_isAutoDebitEnabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.md),
                      child: TextFormField(
                        controller: _autoDebitAccountController,
                        decoration: const InputDecoration(labelText: 'Auto debit account'),
                      ),
                    ),
                ],
              ),
              ExpansionTile(
                title: const Text('Fees & charges (optional)'),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _showCharges,
                onExpansionChanged: (expanded) => setState(() => _showCharges = expanded),
                childrenPadding: EdgeInsets.zero,
                children: [
                  TextFormField(
                    controller: _processingFeeController,
                    decoration: const InputDecoration(labelText: 'Processing fee'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _insuranceController,
                    decoration: const InputDecoration(labelText: 'Insurance amount'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _extraChargesController,
                    decoration: const InputDecoration(labelText: 'Other charges'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _foreclosureController,
                    decoration: const InputDecoration(labelText: 'Foreclosure amount'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _prepaymentChargesController,
                    decoration: const InputDecoration(labelText: 'Prepayment charges'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add EMI',
                isLoading: _isSaving,
                onPressed: _save,
              ),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
