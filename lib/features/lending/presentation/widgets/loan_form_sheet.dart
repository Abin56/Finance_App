import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/interest/interest_calculator.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/widgets/person_form_sheet.dart';
import '../../domain/loan.dart';
import '../../domain/loan_category.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_interest.dart';
import '../../domain/loan_repayment_type.dart';
import '../providers/loan_providers.dart';
import 'add_elsewhere_link.dart';
import 'loan_category_badge.dart';
import 'loan_direction_badge.dart';
import 'loan_emi_ui.dart';

/// Bottom sheet for creating or editing a loan. Repayment type (one-time
/// vs. installments) and interest terms are chosen once at creation and
/// locked afterward — see `Loan`'s dartdoc for why; editing an existing
/// [loan] only exposes name/amount/due date/notes (mirrors
/// `LoanRepository.editLoan`'s own field list), with amount further locked
/// once any payment has been recorded.
/// Sentinel dropdown value for the "Add new person" shortcut — distinct from
/// any real person id and from `null` ("I pay it myself"), so selecting it
/// can be intercepted before it's ever treated as a real [Person.id].
const _addNewPersonValue = '__add_new_person__';

class LoanFormSheet extends ConsumerStatefulWidget {
  const LoanFormSheet({super.key, this.loan, this.initialDirection});

  final Loan? loan;
  final LoanDirection? initialDirection;

  static Future<void> show(
    BuildContext context, {
    Loan? loan,
    LoanDirection? initialDirection,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) =>
          LoanFormSheet(loan: loan, initialDirection: initialDirection),
    );
  }

  @override
  ConsumerState<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends ConsumerState<LoanFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.loan?.name ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.loan == null ? '' : widget.loan!.loanAmount.toStringAsFixed(2),
  );
  late final _notesController = TextEditingController(
    text: widget.loan?.notes ?? '',
  );
  late final _installmentCountController = TextEditingController(
    text: widget.loan?.installmentCount?.toString() ?? '1',
  );
  late final _rateController = TextEditingController(
    text: widget.loan?.interest?.ratePercent.toString() ?? '',
  );
  late final _institutionNameController = TextEditingController(
    text: widget.loan?.institutionName ?? '',
  );
  late final _loanTypeController = TextEditingController(
    text: widget.loan?.loanType ?? '',
  );
  late final _accountNumberController = TextEditingController(
    text: widget.loan?.accountNumber ?? '',
  );
  late final _branchController = TextEditingController(
    text: widget.loan?.branch ?? '',
  );
  final _nameFocusNode = FocusNode();
  final _institutionNameFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();

  late String? _personId = widget.loan?.personId;
  late String? _payerPersonId = widget.loan?.payerPersonId;
  late LoanCategory _category =
      widget.loan?.category ?? LoanCategory.institutional;
  late LoanDirection _direction =
      widget.loan?.direction ?? widget.initialDirection ?? LoanDirection.taken;
  late DateTime _loanDate = widget.loan?.loanDate ?? DateTime.now();
  late DateTime? _dueDate = widget.loan?.dueDate;
  late LoanRepaymentType _repaymentType =
      widget.loan?.repaymentType ?? LoanRepaymentType.oneTime;
  late ScheduleType _installmentFrequency =
      widget.loan?.installmentFrequency ?? ScheduleType.monthly;
  late bool _hasInterest = widget.loan?.interest != null;
  late InterestType _interestType =
      widget.loan?.interest?.type ?? InterestType.flat;
  late InterestPeriod _interestPeriod =
      widget.loan?.interest?.period ?? InterestPeriod.monthly;

  /// Create-only: whether the principal really moved through one of the
  /// user's Accounts. Off by default — then no Transaction and no balance
  /// change are recorded, same as before.
  bool _recordMovement = false;
  String? _movementAccountId;

  /// Create-only: one per Add action, so a retried save can't post the
  /// movement twice (see `LoanRepository.createAgreementWithOrigination`).
  final _idempotencyKey = IdGenerator.generate();
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
    _accountNumberController.dispose();
    _branchController.dispose();
    _nameFocusNode.dispose();
    _institutionNameFocusNode.dispose();
    _amountFocusNode.dispose();
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
      return (
        totalPayable: breakdown.totalPayable,
        totalInterest: breakdown.totalInterest,
      );
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
    if (loan == null || loan.repaymentType != LoanRepaymentType.installment) {
      return false;
    }
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
    if (loan == null || loan.repaymentType != LoanRepaymentType.installment) {
      return false;
    }
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update'),
          ),
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == LoanCategory.personal && _personId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a person')));
      return;
    }
    if (_category == LoanCategory.institutional &&
        _institutionNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Institution name is required')),
      );
      return;
    }
    if (_repaymentType == LoanRepaymentType.oneTime && _dueDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a due date')));
      return;
    }
    if (!_isEditing && _recordMovement && _movementAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pick the account the money moved through, or turn the option off',
          ),
        ),
      );
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
          name: _nameController.text.trim().isEmpty
              ? null
              : _nameController.text.trim(),
          loanAmount: double.parse(_amountController.text.trim()),
          dueDate: _repaymentType == LoanRepaymentType.oneTime
              ? _dueDate
              : null,
          notes: _notesController.text.trim(),
          institutionName: _category == LoanCategory.institutional
              ? _institutionNameController.text.trim()
              : null,
          loanType: _category == LoanCategory.institutional
              ? _loanTypeController.text.trim()
              : null,
          loanNumber: widget.loan?.loanNumber,
          accountNumber: _category == LoanCategory.institutional
              ? _accountNumberController.text.trim()
              : null,
          branch: _category == LoanCategory.institutional
              ? _branchController.text.trim()
              : null,
          payerPersonId: _payerPersonId,
        );
        if (_loanDateChanged) {
          final installments =
              ref.read(installmentsStreamProvider(loan.scheduleId)).value ??
              const [];
          await repository.editLoanDate(
            loan,
            newLoanDate: _loanDate,
            hasPayments: hasPayments,
            currentInstallments: installments,
          );
        }
        if (_termsChanged) {
          final installments =
              ref.read(installmentsStreamProvider(loan.scheduleId)).value ??
              const [];
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
            newInstallmentCount: int.parse(
              _installmentCountController.text.trim(),
            ),
          );
        }
      } else {
        final institutional = _category == LoanCategory.institutional;
        final installment = _repaymentType == LoanRepaymentType.installment;
        final personId = _category == LoanCategory.personal ? _personId : null;
        final institutionName = institutional
            ? _institutionNameController.text.trim()
            : null;
        final loanType = institutional ? _loanTypeController.text.trim() : null;
        final accountNumber = institutional
            ? _accountNumberController.text.trim()
            : null;
        final branch = institutional ? _branchController.text.trim() : null;
        final loanAmount = double.parse(_amountController.text.trim());
        final name = _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim();
        final interest = _hasInterest
            ? LoanInterest(
                type: _interestType,
                ratePercent: double.parse(_rateController.text.trim()),
                period: _interestPeriod,
              )
            : null;
        final dueDate = installment ? null : _dueDate;
        final installmentFrequency = installment ? _installmentFrequency : null;
        final installmentCount = installment
            ? int.parse(_installmentCountController.text.trim())
            : null;
        final notes = _notesController.text.trim();
        if (_recordMovement) {
          // The origination Transaction is tagged as a Loan principal
          // disbursement — it moves the Account balance but never counts as
          // income or spending. Mirrors the web Loan form.
          await repository.createAgreementWithOrigination(
            idempotencyKey: _idempotencyKey,
            movementAccountId: _movementAccountId,
            personId: personId,
            category: _category,
            institutionName: institutionName,
            loanType: loanType,
            accountNumber: accountNumber,
            branch: branch,
            payerPersonId: _payerPersonId,
            loanAmount: loanAmount,
            loanDate: _loanDate,
            repaymentType: _repaymentType,
            direction: _direction,
            name: name,
            interest: interest,
            dueDate: dueDate,
            installmentFrequency: installmentFrequency,
            installmentCount: installmentCount,
            notes: notes,
          );
        } else {
          await repository.createLoan(
            personId: personId,
            category: _category,
            institutionName: institutionName,
            loanType: loanType,
            loanNumber: null,
            accountNumber: accountNumber,
            branch: branch,
            payerPersonId: _payerPersonId,
            loanAmount: loanAmount,
            loanDate: _loanDate,
            repaymentType: _repaymentType,
            direction: _direction,
            name: name,
            interest: interest,
            dueDate: dueDate,
            installmentFrequency: installmentFrequency,
            installmentCount: installmentCount,
            notes: notes,
          );
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save loan: $e')));
      }
    }
  }

  /// Create-only "did the money pass through one of my Accounts?" content,
  /// revealed by its switch. Only lists existing Accounts — new ones are
  /// added in Accounts, never inline here.
  List<Widget> _accountFields(BuildContext context) {
    final received = _direction == LoanDirection.taken;
    final accounts = [
      ...?ref.watch(accountsStreamProvider).value,
    ].where((a) => a.type != AccountType.card && !a.isDeleted).toList();
    final hint = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: loanEmiSecondaryText(context));
    return [
      if (accounts.isEmpty)
        Row(
          children: [
            Expanded(
              child: Text(
                'No accounts yet — add one in Accounts, then come back.',
                style: hint,
              ),
            ),
            const AddElsewhereLink(
              route: AppRoutes.accounts,
              label: 'Go to Accounts',
            ),
          ],
        )
      else ...[
        DropdownButtonFormField<String>(
          initialValue: accounts.any((a) => a.id == _movementAccountId)
              ? _movementAccountId
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: received ? 'Received into' : 'Paid from',
          ),
          hint: const Text('Choose account'),
          items: [
            for (final account in accounts)
              DropdownMenuItem(
                value: account.id,
                child: Text(account.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => _movementAccountId = value),
        ),
        const Align(
          alignment: Alignment.centerRight,
          child: AddElsewhereLink(
            route: AppRoutes.accounts,
            label: 'Add Account',
          ),
        ),
      ],
      Text(
        "Updates this account's balance. It isn't counted as income or "
        'spending — the amount stays tracked as a loan.',
        style: hint,
      ),
    ];
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleStreamProvider).value ?? const <Person>[];
    final preview = _preview;
    final hasPayments = _isEditing
        ? ref.watch(loanTotalReceivedProvider(widget.loan!)) > 0
        : false;
    final received = _direction == LoanDirection.taken;
    final lenderLabel = received ? 'Borrowed from' : 'Lent to';
    final isInstallment = _repaymentType == LoanRepaymentType.installment;
    final canEditLoanDate = !_isEditing || (isInstallment && !hasPayments);
    final secondary = loanEmiSecondaryText(context);

    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _isEditing ? 'Edit loan' : 'Add a Loan',
        confirmLabel: _isEditing ? 'Save changes' : 'Add Loan',
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1 — what kind of loan. Decides the wording of everything below.
            if (!_isEditing) ...[
              const LoanEmiFieldLabel('Did you borrow or lend it?'),
              SegmentedButton<LoanDirection>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LoanDirection.taken,
                    label: Text('I borrowed'),
                  ),
                  ButtonSegment(
                    value: LoanDirection.given,
                    label: Text('I lent'),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (selection) =>
                    setState(() => _direction = selection.first),
              ),
              const SizedBox(height: AppSizes.md),
              LoanEmiFieldLabel(received ? 'Borrowed from a…' : 'Lent to a…'),
              SegmentedButton<LoanCategory>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LoanCategory.institutional,
                    label: Text('Bank / lender'),
                  ),
                  ButtonSegment(
                    value: LoanCategory.personal,
                    label: Text('Person'),
                  ),
                ],
                selected: {_category},
                onSelectionChanged: (selection) =>
                    setState(() => _category = selection.first),
              ),
            ] else
              Wrap(
                spacing: AppSizes.xs,
                runSpacing: AppSizes.xs,
                children: [
                  LoanDirectionBadge(direction: widget.loan!.direction),
                  LoanCategoryBadge(category: widget.loan!.category),
                ],
              ),
            const SizedBox(height: AppSizes.lg),

            // 2 — who and how much.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _category == LoanCategory.personal
                  ? DropdownButtonFormField<String>(
                      key: const ValueKey('category-personal'),
                      initialValue: _personId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: lenderLabel,
                        helperText: _isEditing
                            ? 'Person can\'t be changed after the loan is created'
                            : null,
                      ),
                      hint: const Text('Choose a person'),
                      items: [
                        for (final person in people)
                          DropdownMenuItem(
                            value: person.id,
                            child: Text(person.name),
                          ),
                      ],
                      onChanged: _isEditing
                          ? null
                          : (value) => setState(() => _personId = value),
                    )
                  : TextFormField(
                      key: const ValueKey('category-institutional'),
                      controller: _institutionNameController,
                      focusNode: _institutionNameFocusNode,
                      decoration: InputDecoration(
                        labelText: lenderLabel,
                        hintText: 'e.g. HDFC Bank',
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _amountFocusNode.requestFocus(),
                      validator: (value) =>
                          _category == LoanCategory.institutional &&
                              (value == null || value.trim().isEmpty)
                          ? 'Enter the bank or lender'
                          : null,
                    ),
            ),
            const SizedBox(height: AppSizes.md),
            TextFormField(
              controller: _amountController,
              focusNode: _amountFocusNode,
              enabled: !hasPayments,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Loan amount',
                prefixText: '₹ ',
                helperText: hasPayments
                    ? 'Amount can\'t be changed after a payment has been recorded'
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.amount,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSizes.lg),

            // 3 — how it's repaid.
            if (!_isEditing) ...[
              const LoanEmiFieldLabel('How is it repaid?'),
              SegmentedButton<LoanRepaymentType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LoanRepaymentType.installment,
                    label: Text('In installments'),
                  ),
                  ButtonSegment(
                    value: LoanRepaymentType.oneTime,
                    label: Text('All at once'),
                  ),
                ],
                selected: {_repaymentType},
                onSelectionChanged: (selection) =>
                    setState(() => _repaymentType = selection.first),
              ),
              const SizedBox(height: AppSizes.md),
            ],
            if (!isInstallment)
              _dateTile(
                context,
                title: 'Due date',
                value: _dueDate == null
                    ? 'Choose a date'
                    : _formatDate(_dueDate!),
                onTap: _pickDueDate,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _installmentCountController,
                      decoration: InputDecoration(
                        labelText: 'Installments',
                        helperText: _isEditing
                            ? 'Not less than already paid'
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: DropdownButtonFormField<ScheduleType>(
                      initialValue: _installmentFrequency,
                      decoration: InputDecoration(
                        labelText: 'Paid',
                        helperText: _isEditing
                            ? 'Unpaid ones recalculate'
                            : null,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ScheduleType.monthly,
                          child: Text('Monthly'),
                        ),
                        DropdownMenuItem(
                          value: ScheduleType.weekly,
                          child: Text('Weekly'),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _installmentFrequency =
                            value ?? ScheduleType.monthly,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSizes.sm),
            _dateTile(
              context,
              title: 'Loan date',
              value: _formatDate(_loanDate),
              onTap: canEditLoanDate ? _pickLoanDate : null,
            ),
            if (_isEditing && isInstallment && hasPayments)
              Padding(
                padding: const EdgeInsets.only(top: AppSizes.xs),
                child: Text(
                  'Loan date can\'t be changed after a payment has been recorded',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ),

            // 4 — interest, only when there is some.
            if (!_isEditing || isInstallment) ...[
              const SizedBox(height: AppSizes.md),
              LoanEmiRevealSwitch(
                value: _hasInterest,
                onChanged: (value) => setState(() => _hasInterest = value),
                title: 'It has interest',
                subtitle: 'Leave off for an interest-free loan.',
                children: [
                  TextFormField(
                    controller: _rateController,
                    decoration: const InputDecoration(
                      labelText: 'Interest rate (%)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSizes.md),
                  SegmentedButton<InterestPeriod>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: InterestPeriod.yearly,
                        label: Text('Per year'),
                      ),
                      ButtonSegment(
                        value: InterestPeriod.monthly,
                        label: Text('Per month'),
                      ),
                    ],
                    selected: {_interestPeriod},
                    onSelectionChanged: (selection) =>
                        setState(() => _interestPeriod = selection.first),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  SegmentedButton<InterestType>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: InterestType.reducingBalance,
                        label: Text('Reducing balance'),
                      ),
                      ButtonSegment(
                        value: InterestType.flat,
                        label: Text('Flat'),
                      ),
                    ],
                    selected: {_interestType},
                    onSelectionChanged: (selection) =>
                        setState(() => _interestType = selection.first),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: AppSizes.md),
                    _previewBox(context, preview),
                  ],
                ],
              ),
            ],

            // 5 — linked Account. Its fields only appear once switched on.
            if (!_isEditing) ...[
              const SizedBox(height: AppSizes.md),
              LoanEmiRevealSwitch(
                value: _recordMovement,
                onChanged: (value) => setState(() => _recordMovement = value),
                title: received
                    ? 'Money came into one of my accounts'
                    : 'Money went out of one of my accounts',
                subtitle:
                    "Leave off if it didn't pass through a FlowFi account — "
                    'no balance changes.',
                children: _accountFields(context),
              ),
            ],

            // 6 — everything optional.
            const SizedBox(height: AppSizes.md),
            LoanEmiMoreOptions(
              initiallyExpanded: _isEditing,
              summary: _category == LoanCategory.institutional
                  ? 'Name, who pays, bank details, notes'
                  : 'Name, who pays, notes',
              children: [
                TextFormField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Loan name',
                    hintText: 'e.g. Home Loan',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSizes.md),
                DropdownButtonFormField<String?>(
                  initialValue: _payerPersonId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Who pays the installments?',
                    helperText:
                        'Only if a friend or family member pays it for you',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('I pay it myself'),
                    ),
                    for (final person in people)
                      DropdownMenuItem(
                        value: person.id,
                        child: Text(person.name),
                      ),
                    const DropdownMenuItem(
                      value: _addNewPersonValue,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: AppSizes.xs),
                          Text('Add new person'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == _addNewPersonValue) {
                      final newPersonId = await PersonFormSheet.show(context);
                      if (newPersonId != null) {
                        setState(() => _payerPersonId = newPersonId);
                      }
                      return;
                    }
                    setState(() => _payerPersonId = value);
                  },
                ),
                if (_category == LoanCategory.institutional) ...[
                  const SizedBox(height: AppSizes.lg),
                  const SectionLabel('Bank details'),
                  const SizedBox(height: AppSizes.sm),
                  TextFormField(
                    controller: _loanTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Type of loan',
                      hintText: 'e.g. Personal, Vehicle, Education',
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _accountNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Bank account number',
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _branchController,
                    decoration: const InputDecoration(labelText: 'Branch'),
                  ),
                ],
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTile(
    BuildContext context, {
    required String title,
    required String value,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: onTap,
    );
  }

  Widget _previewBox(
    BuildContext context,
    ({double totalPayable, double totalInterest}) preview,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total to pay: ${CurrencyFormatter.instance.format(preview.totalPayable)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Total interest: ${CurrencyFormatter.instance.format(preview.totalInterest)}',
          ),
        ],
      ),
    );
  }
}
