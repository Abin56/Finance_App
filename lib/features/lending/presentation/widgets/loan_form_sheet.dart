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
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan.dart';
import '../../domain/loan_category.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_interest.dart';
import '../../domain/loan_repayment_type.dart';
import '../providers/loan_providers.dart';
import 'loan_category_badge.dart';
import 'loan_direction_badge.dart';

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
      showDragHandle: false,
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
  late final _institutionNameController = TextEditingController(text: widget.loan?.institutionName ?? '');
  late final _loanTypeController = TextEditingController(text: widget.loan?.loanType ?? '');
  late final _loanNumberController = TextEditingController(text: widget.loan?.loanNumber ?? '');
  late final _accountNumberController = TextEditingController(text: widget.loan?.accountNumber ?? '');
  late final _branchController = TextEditingController(text: widget.loan?.branch ?? '');

  late String? _personId = widget.loan?.personId;
  late String? _payerPersonId = widget.loan?.payerPersonId;
  late LoanCategory _category = widget.loan?.category ?? LoanCategory.personal;
  late LoanDirection _direction = widget.loan?.direction ?? LoanDirection.given;
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
    _institutionNameController.dispose();
    _loanTypeController.dispose();
    _loanNumberController.dispose();
    _accountNumberController.dispose();
    _branchController.dispose();
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
        installmentsPerYear: _repaymentType == LoanRepaymentType.installment
            ? _installmentsPerYearFor(_installmentFrequency)
            : null,
      );
      return (totalPayable: breakdown.totalPayable, totalInterest: breakdown.totalInterest);
    } catch (_) {
      return null;
    }
  }

  /// Mirrors `LoanRepository._installmentsPerYearFor` exactly, so this
  /// preview always matches what `createLoan` will actually persist —
  /// weekly gets its true per-year count (52) instead of being forced
  /// through the monthly bucket.
  int _installmentsPerYearFor(ScheduleType scheduleType) {
    switch (scheduleType) {
      case ScheduleType.weekly:
        return 52;
      case ScheduleType.monthly:
      case ScheduleType.oneTime:
      case ScheduleType.custom:
        return 12;
    }
  }

  /// Whether the term-driving fields (interest, frequency, count) differ
  /// from what [widget.loan] currently has — mirrors `EmiFormSheet._termsChanged`.
  /// Always false for one-time loans (they have no editable terms).
  bool get _termsChanged {
    final loan = widget.loan;
    if (loan == null || loan.repaymentType != LoanRepaymentType.installment) return false;
    final newCount = int.tryParse(_installmentCountController.text.trim());
    if (newCount == null || newCount != loan.installmentCount) return true;
    if (_installmentFrequency != loan.installmentFrequency) return true;
    final hadInterest = loan.interest != null;
    if (_hasInterest != hadInterest) return true;
    if (_hasInterest) {
      final newRate = double.tryParse(_rateController.text.trim());
      if (newRate != loan.interest!.ratePercent) return true;
      if (_interestType != loan.interest!.type) return true;
      if (_interestPeriod != loan.interest!.period) return true;
    }
    return false;
  }

  /// Whether Loan Date differs from [widget.loan]'s current [Loan.loanDate]
  /// — mirrors `EmiFormSheet._startDateChanged`. Only meaningful for
  /// installment loans; one-time loans use [_dueDate] instead.
  bool get _loanDateChanged {
    final loan = widget.loan;
    if (loan == null || loan.repaymentType != LoanRepaymentType.installment) return false;
    return !_loanDate.isAtSameMomentAs(loan.loanDate);
  }

  Future<bool> _confirmLoanDateChange() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Loan Date?'),
        content: const Text(
          'This regenerates every payment in this loan\'s schedule against the new date. Since no payments have '
          'been recorded yet, nothing else is affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Update')),
        ],
      ),
    ).then((value) => value ?? false);
  }

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
    if (_category == LoanCategory.personal && _personId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a person')));
      return;
    }
    if (_category == LoanCategory.institutional && _institutionNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Institution name is required')));
      return;
    }
    if (_repaymentType == LoanRepaymentType.oneTime && _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a due date')));
      return;
    }

    if (_isEditing && _loanDateChanged) {
      final confirmed = await _confirmLoanDateChange();
      if (!confirmed) return;
    }

    if (_isEditing && _termsChanged) {
      final loan = widget.loan!;
      final remaining = ref.read(loanRemainingAmountProvider(loan));
      final confirmed = await _confirmTermsChange(remaining);
      if (!confirmed) return;
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
          institutionName:
              _category == LoanCategory.institutional ? _institutionNameController.text.trim() : null,
          loanType: _category == LoanCategory.institutional ? _loanTypeController.text.trim() : null,
          loanNumber: _category == LoanCategory.institutional ? _loanNumberController.text.trim() : null,
          accountNumber: _category == LoanCategory.institutional ? _accountNumberController.text.trim() : null,
          branch: _category == LoanCategory.institutional ? _branchController.text.trim() : null,
          payerPersonId: _payerPersonId,
        );
        if (_loanDateChanged) {
          final installments = ref.read(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
          await repository.editLoanDate(
            loan,
            newLoanDate: _loanDate,
            hasPayments: hasPayments,
            currentInstallments: installments,
          );
        }
        if (_termsChanged) {
          final installments = ref.read(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
          await repository.editLoanTerms(
            loan,
            currentInstallments: installments,
            interest: _hasInterest
                ? LoanInterest(
                    type: _interestType,
                    ratePercent: double.parse(_rateController.text.trim()),
                    period: _interestPeriod,
                  )
                : null,
            installmentFrequency: _installmentFrequency,
            newInstallmentCount: int.parse(_installmentCountController.text.trim()),
          );
        }
      } else {
        await repository.createLoan(
          personId: _category == LoanCategory.personal ? _personId : null,
          category: _category,
          institutionName:
              _category == LoanCategory.institutional ? _institutionNameController.text.trim() : null,
          loanType: _category == LoanCategory.institutional ? _loanTypeController.text.trim() : null,
          loanNumber: _category == LoanCategory.institutional ? _loanNumberController.text.trim() : null,
          accountNumber: _category == LoanCategory.institutional ? _accountNumberController.text.trim() : null,
          branch: _category == LoanCategory.institutional ? _branchController.text.trim() : null,
          payerPersonId: _payerPersonId,
          loanAmount: double.parse(_amountController.text.trim()),
          loanDate: _loanDate,
          repaymentType: _repaymentType,
          direction: _direction,
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

    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _isEditing ? 'Edit loan' : 'Add loan',
        confirmLabel: _isEditing ? 'Save changes' : 'Add loan',
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              const SectionLabel('Loan Details'),
              const SizedBox(height: AppSizes.sm),
              if (!_isEditing) ...[
                SegmentedButton<LoanCategory>(
                  segments: [
                    for (final category in LoanCategory.values)
                      ButtonSegment(value: category, label: Text(category.formLabel)),
                  ],
                  selected: {_category},
                  onSelectionChanged: (selection) => setState(() => _category = selection.first),
                ),
                const SizedBox(height: AppSizes.md),
              ] else
                LoanCategoryBadge(category: widget.loan!.category),
              const SizedBox(height: AppSizes.sm),
              if (!_isEditing) ...[
                Text('Which is it?', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AppSizes.xs),
                SegmentedButton<LoanDirection>(
                  segments: [
                    for (final direction in LoanDirection.values)
                      ButtonSegment(value: direction, label: Text(direction.formLabel)),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (selection) => setState(() => _direction = selection.first),
                ),
                const SizedBox(height: AppSizes.md),
              ] else
                LoanDirectionBadge(direction: widget.loan!.direction),
              const SizedBox(height: AppSizes.sm),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _category == LoanCategory.personal
                      ? KeyedSubtree(
                          key: const ValueKey('category-personal'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // TODO(future enhancement, post-Milestone 2): support inline
                              // Person creation from this dropdown ("+ Create New Person"
                              // -> bottom sheet -> auto-select), so a brand-new account
                              // isn't blocked from adding a loan by needing to leave this
                              // form first.
                              DropdownButtonFormField<String>(
                                initialValue: _personId,
                                decoration: InputDecoration(
                                  labelText: _direction == LoanDirection.given
                                      ? 'Who did you lend it to?'
                                      : 'Who did you borrow it from?',
                                  helperText:
                                      _isEditing ? 'Person can\'t be changed after the loan is created' : null,
                                ),
                                items: [
                                  for (final person in people)
                                    DropdownMenuItem(value: person.id, child: Text(person.name)),
                                ],
                                onChanged: _isEditing ? null : (value) => setState(() => _personId = value),
                              ),
                            ],
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('category-institutional'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _institutionNameController,
                                decoration: const InputDecoration(labelText: 'Bank / Institution name'),
                                validator: (value) => _category == LoanCategory.institutional &&
                                        (value == null || value.trim().isEmpty)
                                    ? 'Institution name is required'
                                    : null,
                              ),
                              const SizedBox(height: AppSizes.md),
                              TextFormField(
                                controller: _loanTypeController,
                                decoration: const InputDecoration(
                                  labelText: 'Type of loan (optional)',
                                  hintText: 'e.g. Personal Loan, Vehicle Loan, Education Loan',
                                ),
                              ),
                              const SizedBox(height: AppSizes.md),
                              TextFormField(
                                controller: _loanNumberController,
                                decoration: const InputDecoration(labelText: 'Loan account number (optional)'),
                              ),
                              const SizedBox(height: AppSizes.md),
                              TextFormField(
                                controller: _accountNumberController,
                                decoration: const InputDecoration(labelText: 'Bank account number (optional)'),
                              ),
                              const SizedBox(height: AppSizes.md),
                              TextFormField(
                                controller: _branchController,
                                decoration: const InputDecoration(labelText: 'Branch (optional)'),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String?>(
                initialValue: _payerPersonId,
                decoration: const InputDecoration(
                  labelText: 'Who actually pays the EMIs? (optional)',
                  helperText:
                      'Only pick someone if this is a loan that a friend or family member actually pays for you',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('I pay it myself')),
                  for (final person in people) DropdownMenuItem(value: person.id, child: Text(person.name)),
                ],
                onChanged: (value) => setState(() => _payerPersonId = value),
              ),
              const SizedBox(height: AppSizes.sm),
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
                enabled: !_isEditing || (_repaymentType == LoanRepaymentType.installment && !hasPayments),
                title: const Text('Loan date'),
                subtitle: Text('${_loanDate.day}/${_loanDate.month}/${_loanDate.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: !_isEditing || (_repaymentType == LoanRepaymentType.installment && !hasPayments)
                    ? _pickLoanDate
                    : null,
              ),
              if (_isEditing && _repaymentType == LoanRepaymentType.installment && hasPayments)
                const Padding(
                  padding: EdgeInsets.only(top: AppSizes.xs),
                  child: Text(
                    'Loan date can\'t be changed after a payment has been recorded',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: AppSizes.lg),
              const SectionLabel('Repayment'),
              const SizedBox(height: AppSizes.sm),
              if (!_isEditing) ...[
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
              else ...[
                DropdownButtonFormField<ScheduleType>(
                  initialValue: _installmentFrequency,
                  decoration: InputDecoration(
                    labelText: 'Frequency',
                    helperText: _isEditing ? 'Can be changed — only unpaid payments are recalculated' : null,
                  ),
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
                    labelText: 'Number of monthly payments',
                    helperText: _isEditing ? 'Can\'t be less than the number of payments already made' : null,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (!_isEditing || _repaymentType == LoanRepaymentType.installment) ...[
                const SizedBox(height: AppSizes.lg),
                const SectionLabel('Interest'),
                const SizedBox(height: AppSizes.xs),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Add interest'),
                  value: _hasInterest,
                  onChanged: (value) => setState(() => _hasInterest = value),
                ),
              ],
              if (_hasInterest && (!_isEditing || _repaymentType == LoanRepaymentType.installment)) ...[
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
              const SizedBox(height: AppSizes.lg),
              const SectionLabel('Notes'),
              const SizedBox(height: AppSizes.sm),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
          ],
        ),
      ),
    );
  }
}
