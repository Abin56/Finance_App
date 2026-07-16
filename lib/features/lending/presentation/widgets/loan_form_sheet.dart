import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/interest/interest_calculator.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan.dart';
import '../../domain/loan_interest.dart';
import '../../domain/loan_repayment_type.dart';
import '../providers/loan_providers.dart';

/// Bottom sheet for creating or editing a loan. Repayment type (one-time
/// vs. installments) and interest terms are chosen once at creation and
/// locked afterward — see `Loan`'s dartdoc for why; editing an existing
/// [loan] only exposes name/amount/due date/notes (mirrors
/// `LoanRepository.editLoan`'s own field list), with amount further locked
/// once any payment has been recorded.
class LoanFormSheet extends ConsumerStatefulWidget {
  const LoanFormSheet({super.key, this.loan});

  final Loan? loan;

  static Future<void> show(BuildContext context, {Loan? loan}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LoanFormSheet(loan: loan),
    );
  }

  @override
  ConsumerState<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends ConsumerState<LoanFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.loan?.name ?? '');
  late final _amountController = TextEditingController(
    text: widget.loan == null ? '' : widget.loan!.loanAmount.toStringAsFixed(2),
  );
  late final _notesController = TextEditingController(text: widget.loan?.notes ?? '');
  late final _installmentCountController = TextEditingController(
    text: widget.loan?.installmentCount?.toString() ?? '1',
  );
  late final _rateController = TextEditingController(
    text: widget.loan?.interest?.ratePercent.toString() ?? '',
  );

  late String? _personId = widget.loan?.personId;
  late DateTime _loanDate = widget.loan?.loanDate ?? DateTime.now();
  late DateTime? _dueDate = widget.loan?.dueDate;
  late LoanRepaymentType _repaymentType = widget.loan?.repaymentType ?? LoanRepaymentType.oneTime;
  late ScheduleType _installmentFrequency = widget.loan?.installmentFrequency ?? ScheduleType.monthly;
  late bool _hasInterest = widget.loan?.interest != null;
  late InterestType _interestType = widget.loan?.interest?.type ?? InterestType.flat;
  late InterestPeriod _interestPeriod = widget.loan?.interest?.period ?? InterestPeriod.monthly;
  bool _isSaving = false;

  bool get _isEditing => widget.loan != null;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _installmentCountController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _pickLoanDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _loanDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _loanDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _loanDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
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
    final count = _repaymentType == LoanRepaymentType.oneTime
        ? 1
        : int.tryParse(_installmentCountController.text.trim());
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_personId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a person')));
      return;
    }
    if (_repaymentType == LoanRepaymentType.oneTime && _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a due date')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(loanRepositoryProvider);
      if (_isEditing) {
        final loan = widget.loan!;
        final hasPayments = ref.read(loanTotalReceivedProvider(loan)) > 0;
        await repository.editLoan(
          loan,
          hasPayments: hasPayments,
          name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
          loanAmount: double.parse(_amountController.text.trim()),
          dueDate: _repaymentType == LoanRepaymentType.oneTime ? _dueDate : null,
          notes: _notesController.text.trim(),
        );
      } else {
        await repository.createLoan(
          personId: _personId!,
          loanAmount: double.parse(_amountController.text.trim()),
          loanDate: _loanDate,
          repaymentType: _repaymentType,
          name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
          interest: _hasInterest
              ? LoanInterest(
                  type: _interestType,
                  ratePercent: double.parse(_rateController.text.trim()),
                  period: _interestPeriod,
                )
              : null,
          dueDate: _repaymentType == LoanRepaymentType.oneTime ? _dueDate : null,
          installmentFrequency: _repaymentType == LoanRepaymentType.installment ? _installmentFrequency : null,
          installmentCount: _repaymentType == LoanRepaymentType.installment
              ? int.parse(_installmentCountController.text.trim())
              : null,
          notes: _notesController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save loan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleStreamProvider).value ?? const <Person>[];
    final preview = _preview;
    final hasPayments = _isEditing ? ref.watch(loanTotalReceivedProvider(widget.loan!)) > 0 : false;

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
              Text(_isEditing ? 'Edit loan' : 'Add loan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              // TODO(future enhancement, post-Milestone 2): support inline Person
              // creation from this dropdown ("+ Create New Person" -> bottom sheet
              // -> auto-select), so a brand-new account isn't blocked from adding
              // a loan by needing to leave this form first.
              DropdownButtonFormField<String>(
                initialValue: _personId,
                decoration: InputDecoration(
                  labelText: 'Person',
                  helperText: _isEditing ? 'Person can\'t be changed after the loan is created' : null,
                ),
                items: [
                  for (final person in people) DropdownMenuItem(value: person.id, child: Text(person.name)),
                ],
                onChanged: _isEditing ? null : (value) => setState(() => _personId = value),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Loan name (optional)'),
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
                title: const Text('Loan date'),
                subtitle: Text('${_loanDate.day}/${_loanDate.month}/${_loanDate.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _isEditing ? null : _pickLoanDate,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: AppSizes.md),
                Text('Repayment', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSizes.sm),
                SegmentedButton<LoanRepaymentType>(
                  segments: const [
                    ButtonSegment(value: LoanRepaymentType.oneTime, label: Text('One-time')),
                    ButtonSegment(value: LoanRepaymentType.installment, label: Text('Monthly Payments')),
                  ],
                  selected: {_repaymentType},
                  onSelectionChanged: (selection) => setState(() => _repaymentType = selection.first),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              if (_repaymentType == LoanRepaymentType.oneTime)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(
                    _dueDate == null ? 'Choose a date' : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _pickDueDate,
                )
              else if (!_isEditing) ...[
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
                  decoration: const InputDecoration(labelText: 'Number of monthly payments'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (!_isEditing) ...[
                const SizedBox(height: AppSizes.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Add interest'),
                  value: _hasInterest,
                  onChanged: (value) => setState(() => _hasInterest = value),
                ),
              ],
              if (_hasInterest && !_isEditing) ...[
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
                  decoration: const InputDecoration(labelText: 'Interest rate (%)'),
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
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add loan',
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
