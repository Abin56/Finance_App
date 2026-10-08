import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/schedule_type.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../lending/domain/loan.dart';
import '../../../lending/domain/loan_category.dart';
import '../../../lending/domain/loan_direction.dart';
import '../../../lending/domain/loan_interest.dart';
import '../../../lending/domain/loan_repayment_type.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/widgets/person_form_sheet.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/unified_create_request.dart';

export '../../domain/unified_create_request.dart' show UnifiedCreateKind;

const _addNewPerson = '__add_new_person__';

class UnifiedAgreementCreateScreen extends ConsumerStatefulWidget {
  const UnifiedAgreementCreateScreen({super.key, this.initialKind});
  final UnifiedCreateKind? initialKind;

  @override
  ConsumerState<UnifiedAgreementCreateScreen> createState() =>
      _UnifiedAgreementCreateScreenState();
}

class _UnifiedAgreementCreateScreenState
    extends ConsumerState<UnifiedAgreementCreateScreen> {
  late UnifiedCreateKind? _kind = widget.initialKind;
  var _step = 0;
  late var _funding = widget.initialKind == UnifiedCreateKind.lent
      ? LoanFundingSource.person
      : LoanFundingSource.bank;
  var _interestType = InterestType.reducingBalance;
  var _repayment = UnifiedRepayment.scheduled;
  DateTime? _dueDate;
  DateTime _loanDate = DateTime.now();
  DateTime _firstEmiDate = DateTime.now();
  String? _personId, _cardId, _purchaseTransactionId, _movementAccountId;
  var _recordMovement = false;
  bool _saving = false;

  /// One idempotency key per wizard session: a retry after a failure or
  /// timeout reuses it, so the repository can never create the agreement (or
  /// move the money) twice.
  final _idempotencyKey = IdGenerator.generate();
  final _name = TextEditingController();
  final _provider = TextEditingController();
  final _amount = TextEditingController();
  final _downPayment = TextEditingController(text: '0');
  final _count = TextEditingController(text: '12');
  final _rate = TextEditingController();

  UnifiedCreateForm get _form => UnifiedCreateForm(
    kind: _kind,
    funding: _funding,
    name: _name.text,
    provider: _provider.text,
    personId: _personId,
    amount: _amount.text,
    downPayment: _downPayment.text,
    repayment: _repayment,
    count: _count.text,
    dueDate: _dueDate,
    rate: _rate.text,
    interestType: _interestType,
    cardId: _cardId,
    purchaseId: _purchaseTransactionId,
    recordMovement: _recordMovement,
    movementAccountId: _movementAccountId,
  );

  @override
  void dispose() {
    for (final controller in [
      _name,
      _provider,
      _amount,
      _downPayment,
      _count,
      _rate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final accounts = (ref.watch(accountsStreamProvider).value ?? const [])
        .where((a) => a.type != AccountType.card && !a.isDeleted)
        .toList();
    final transactions =
        ref.watch(transactionsStreamProvider).value ?? const [];
    final selectedCard = cards.where((card) => card.id == _cardId).firstOrNull;
    final purchases = selectedCard == null
        ? const []
        : transactions
              .where(
                (item) =>
                    item.accountId == selectedCard.accountId &&
                    item.type == TransactionType.expense &&
                    item.deletedAt == null,
              )
              .toList();
    final form = _form;
    final figures = unifiedCreateFigures(form);
    final error = unifiedCreateError(form);
    final movementLabel = movementChoiceLabel(form);
    final movementAccount = accounts
        .where((a) => a.id == _movementAccountId)
        .firstOrNull;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Loan / Installment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text('Step ${_step + 1} of 3', style: textTheme.labelLarge),
            const SizedBox(height: AppSizes.md),
            if (_step == 0) ...[
              Text('What are you adding?', style: textTheme.headlineSmall),
              const SizedBox(height: AppSizes.lg),
              for (final value in UnifiedCreateKind.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: Icon(
                        _kind == value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(_kindLabel(value)),
                      onTap: () => setState(() {
                        _kind = value;
                        _funding = value == UnifiedCreateKind.lent
                            ? LoanFundingSource.person
                            : LoanFundingSource.bank;
                        _repayment = UnifiedRepayment.scheduled;
                        _recordMovement = false;
                        _movementAccountId = null;
                      }),
                    ),
                  ),
                ),
            ] else if (_step == 1 && _kind != null) ...[
              Text('Agreement details', style: textTheme.headlineSmall),
              const SizedBox(height: AppSizes.lg),
              DropdownButtonFormField<LoanFundingSource>(
                initialValue: _funding,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Funding source'),
                items: [
                  for (final value in LoanFundingSource.values.where(
                    (value) =>
                        _kind != UnifiedCreateKind.lent ||
                        value == LoanFundingSource.person,
                  ))
                    DropdownMenuItem(
                      value: value,
                      child: Text(fundingLabel(value)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _funding = value ?? LoanFundingSource.other;
                  _personId = null;
                  _cardId = null;
                  _purchaseTransactionId = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _kind == UnifiedCreateKind.installmentPurchase
                      ? 'What did you buy?'
                      : 'Name / purpose',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
              if (_funding == LoanFundingSource.person)
                DropdownButtonFormField<String>(
                  key: ValueKey('person-$_personId-${people.length}'),
                  initialValue: people.any((p) => p.id == _personId)
                      ? _personId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Person'),
                  items: [
                    for (final person in people)
                      DropdownMenuItem(
                        value: person.id,
                        child: Text(person.name),
                      ),
                    const DropdownMenuItem(
                      value: _addNewPerson,
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: AppSizes.xs),
                          Text('Add new person'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == _addNewPerson) {
                      // Reuses the existing People flow; the new Person is
                      // selected as soon as the live people stream has it.
                      final newPersonId = await PersonFormSheet.show(context);
                      if (mounted) setState(() => _personId = newPersonId);
                      return;
                    }
                    setState(() => _personId = value);
                  },
                )
              else if (_funding == LoanFundingSource.creditCard) ...[
                DropdownButtonFormField<String>(
                  initialValue: _cardId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'FlowFi credit card',
                  ),
                  items: [
                    for (final card in cards)
                      DropdownMenuItem(
                        value: card.id,
                        child: Text(
                          'Card •••• ${card.lastFourDigits ?? '----'}',
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _cardId = value;
                    _purchaseTransactionId = null;
                  }),
                ),
                const SizedBox(height: AppSizes.md),
                DropdownButtonFormField<String?>(
                  initialValue: _purchaseTransactionId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Original card purchase (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Purchase not recorded / link later'),
                    ),
                    for (final item in purchases)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          item.description.isEmpty
                              ? 'Purchase'
                              : item.description,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _purchaseTransactionId = value),
                ),
              ] else
                TextField(
                  controller: _provider,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Provider'),
                ),
              const SizedBox(height: AppSizes.md),
              TextField(
                controller: _amount,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _kind == UnifiedCreateKind.installmentPurchase
                      ? 'Purchase amount'
                      : 'Principal',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_kind == UnifiedCreateKind.installmentPurchase) ...[
                const SizedBox(height: AppSizes.md),
                TextField(
                  controller: _downPayment,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Down payment'),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                const SizedBox(height: AppSizes.md),
                Text('How will it be repaid?', style: textTheme.labelLarge),
                const SizedBox(height: AppSizes.sm),
                SegmentedButton<UnifiedRepayment>(
                  segments: const [
                    ButtonSegment(
                      value: UnifiedRepayment.scheduled,
                      label: Text('Scheduled'),
                    ),
                    ButtonSegment(
                      value: UnifiedRepayment.oneTime,
                      label: Text('One-time'),
                    ),
                  ],
                  selected: {_repayment},
                  onSelectionChanged: (value) =>
                      setState(() => _repayment = value.first),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Loan Taken Date'),
                subtitle: Text(_formatDate(_loanDate)),
                onTap: _pickLoanDate,
              ),
              const SizedBox(height: AppSizes.md),
              if (form.isOneTime)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Repay by'),
                  subtitle: Text(
                    _dueDate == null ? 'Choose a date' : _formatDate(_dueDate!),
                  ),
                  onTap: _pickDueDate,
                )
              else
                Column(
                  children: [
                    TextField(
                      controller: _count,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly payments',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('First EMI Date'),
                      subtitle: Text(_formatDate(_firstEmiDate)),
                      onTap: _pickFirstEmiDate,
                    ),
                  ],
                ),
              const SizedBox(height: AppSizes.md),
              TextField(
                controller: _rate,
                textInputAction: TextInputAction.done,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Interest % (optional)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_rate.text.isNotEmpty) ...[
                const SizedBox(height: AppSizes.md),
                SegmentedButton<InterestType>(
                  segments: const [
                    ButtonSegment(
                      value: InterestType.reducingBalance,
                      label: Text('Reducing'),
                    ),
                    ButtonSegment(
                      value: InterestType.flat,
                      label: Text('Flat'),
                    ),
                  ],
                  selected: {_interestType},
                  onSelectionChanged: (value) =>
                      setState(() => _interestType = value.first),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.md),
                  child: movementLabel == null
                      ? const Text('No account will change.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(movementLabel),
                              value: _recordMovement,
                              onChanged: (value) =>
                                  setState(() => _recordMovement = value),
                            ),
                            if (_recordMovement)
                              DropdownButtonFormField<String>(
                                initialValue: _movementAccountId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Account',
                                ),
                                items: [
                                  for (final account in accounts)
                                    DropdownMenuItem(
                                      value: account.id,
                                      child: Text(account.name),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _movementAccountId = value),
                              )
                            else
                              const Text(
                                'Agreement already exists — no account will change.',
                              ),
                          ],
                        ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSizes.sm),
                Text(error, style: textTheme.bodySmall),
              ],
            ] else ...[
              Text('Review', style: textTheme.headlineSmall),
              const SizedBox(height: AppSizes.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name.text, style: textTheme.titleLarge),
                      const SizedBox(height: AppSizes.md),
                      Text('Principal: ${_rupees(figures.principal)}'),
                      if (_kind == UnifiedCreateKind.installmentPurchase)
                        Text(
                          'Purchase: ${_rupees(figures.purchase)} · Down payment: ${_rupees(figures.down)}',
                        ),
                      Text(
                        form.isOneTime
                            ? 'One-time repayment by ${_formatDate(_dueDate!)}'
                            : '${_count.text} monthly payments',
                      ),
                      Text('Funding: ${fundingLabel(_funding)}'),
                      Text(
                        figures.movesMoney
                            ? 'Account movement: ${movementAccount?.name ?? 'Account'} '
                                  '${figures.movementDelta >= 0 ? '+' : '−'}'
                                  '${_rupees(figures.movementDelta.abs())}'
                            : 'Account movement: none',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      // Pinned above the keyboard so Back/Continue/Create stay reachable on
      // small screens without scrolling to the end of the form.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.sm,
            AppSizes.lg,
            AppSizes.md + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => _step == 0
                            ? Navigator.pop(context)
                            : setState(() => _step--),
                  child: Text(_step == 0 ? 'Cancel' : 'Back'),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: FilledButton(
                  onPressed:
                      _saving ||
                          (_step == 0 && _kind == null) ||
                          (_step > 0 && error != null)
                      ? null
                      : () => _step < 2 ? setState(() => _step++) : _create(),
                  child: Text(
                    _step < 2
                        ? 'Continue'
                        : _saving
                        ? 'Creating…'
                        : 'Create agreement',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) setState(() => _dueDate = picked);
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

  Future<void> _pickFirstEmiDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstEmiDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _firstEmiDate = picked);
  }

  Future<void> _create() async {
    if (_saving) return;
    setState(() => _saving = true);
    final form = _form;
    final figures = unifiedCreateFigures(form);
    final personal = _funding == LoanFundingSource.person;
    final purchasePlan = _kind == UnifiedCreateKind.installmentPurchase;
    try {
      final result = await ref
          .read(loanRepositoryProvider)
          .createAgreementWithOrigination(
            idempotencyKey: _idempotencyKey,
            agreementKind: purchasePlan
                ? LoanAgreementKind.installmentPurchase
                : LoanAgreementKind.loan,
            fundingSource: _funding,
            linkedCreditCardId: _funding == LoanFundingSource.creditCard
                ? _cardId
                : null,
            purchaseTransactionId: _funding == LoanFundingSource.creditCard
                ? _purchaseTransactionId
                : null,
            purchaseAmount: purchasePlan ? figures.purchase : null,
            downPayment: purchasePlan ? figures.down : null,
            personId: personal ? _personId : null,
            category: personal
                ? LoanCategory.personal
                : LoanCategory.institutional,
            institutionName: personal
                ? null
                : (_provider.text.trim().isEmpty
                      ? fundingLabel(_funding)
                      : _provider.text.trim()),
            direction: _kind == UnifiedCreateKind.lent
                ? LoanDirection.given
                : LoanDirection.taken,
            loanAmount: figures.principal,
            loanDate: _loanDate,
            firstDueDate: form.isOneTime ? null : _firstEmiDate,
            repaymentType: form.isOneTime
                ? LoanRepaymentType.oneTime
                : LoanRepaymentType.installment,
            dueDate: form.isOneTime ? _dueDate : null,
            installmentFrequency: form.isOneTime ? null : ScheduleType.monthly,
            installmentCount: form.isOneTime ? null : int.parse(_count.text),
            name: _name.text.trim(),
            interest: _rate.text.trim().isEmpty
                ? null
                : LoanInterest(
                    type: _interestType,
                    ratePercent: double.parse(_rate.text),
                    period: InterestPeriod.yearly,
                  ),
            movementAccountId: figures.movesMoney ? _movementAccountId : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyCreated
                  ? 'Agreement was already added'
                  : 'Agreement added',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error is AppException ? error.message : '$error'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

String _rupees(double value) => '₹${value.toStringAsFixed(2)}';

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _kindLabel(UnifiedCreateKind value) => switch (value) {
  UnifiedCreateKind.borrowed => 'Loan I Took',
  UnifiedCreateKind.lent => 'Loan I Gave',
  UnifiedCreateKind.installmentPurchase => 'Purchase on Installments',
};
