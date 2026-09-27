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
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/domain/credit_card_profile.dart';
import '../../../credit_cards/domain/credit_card_status.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../lending/presentation/widgets/add_elsewhere_link.dart';
import '../../../lending/presentation/widgets/loan_emi_ui.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/emi.dart';
import '../../domain/emi_interest.dart';
import '../../domain/emi_loan_type.dart';
import '../providers/emi_providers.dart';

/// How a card-linked EMI came about — only picks the form wording; both lock
/// the principal against the card. Not persisted (mirrors the web form).
enum _CardEmiKind { creditCardLoan, productPurchase }

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
      showDragHandle: false,
      builder: (_) => EmiFormSheet(emi: emi),
    );
  }

  @override
  ConsumerState<EmiFormSheet> createState() => _EmiFormSheetState();
}

class _EmiFormSheetState extends ConsumerState<EmiFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.emi?.name ?? '',
  );
  late final _lenderController = TextEditingController(
    text: widget.emi?.lenderName ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.emi == null
        ? ''
        : widget.emi!.principalAmount.toStringAsFixed(2),
  );
  late final _notesController = TextEditingController(
    text: widget.emi?.notes ?? '',
  );
  late final _installmentCountController = TextEditingController(
    text: widget.emi?.installmentCount.toString() ?? '',
  );
  late final _rateController = TextEditingController(
    text: widget.emi?.interest?.ratePercent.toString() ?? '',
  );
  late final _loanNumberController = TextEditingController(
    text: widget.emi?.loanNumber ?? '',
  );
  late final _branchController = TextEditingController(
    text: widget.emi?.branch ?? '',
  );
  late final _customerIdController = TextEditingController(
    text: widget.emi?.customerId ?? '',
  );
  late final _processingFeeController = TextEditingController(
    text: widget.emi == null || widget.emi!.processingFee == 0
        ? ''
        : widget.emi!.processingFee.toStringAsFixed(2),
  );
  late final _insuranceController = TextEditingController(
    text: widget.emi == null || widget.emi!.insuranceAmount == 0
        ? ''
        : widget.emi!.insuranceAmount.toStringAsFixed(2),
  );
  late final _extraChargesController = TextEditingController(
    text: widget.emi == null || widget.emi!.extraCharges == 0
        ? ''
        : widget.emi!.extraCharges.toStringAsFixed(2),
  );
  late final _foreclosureController = TextEditingController(
    text: widget.emi?.foreclosureAmount?.toStringAsFixed(2) ?? '',
  );
  late final _prepaymentChargesController = TextEditingController(
    text: widget.emi?.prepaymentCharges?.toStringAsFixed(2) ?? '',
  );
  late final _autoDebitAccountController = TextEditingController(
    text: widget.emi?.autoDebitAccount ?? '',
  );
  late final _dueDayOfMonthController = TextEditingController(
    text: widget.emi?.dueDayOfMonth?.toString() ?? '',
  );

  late String? _categoryId = widget.emi?.categoryId;
  late DateTime _startDate = widget.emi?.startDate ?? DateTime.now();
  late ScheduleType _installmentFrequency =
      widget.emi?.installmentFrequency ?? ScheduleType.monthly;
  late bool _hasInterest = widget.emi?.interest != null;
  // Real bank loans (home/personal/vehicle/etc.) are almost always quoted
  // as an annual reducing-balance rate — defaulting to that (rather than
  // flat/per-month) avoids a silent unit mismatch where a user types an
  // annual-style rate (e.g. "15.12") without noticing the toggles, producing
  // a nonsensical multi-times-the-principal preview.
  late InterestType _interestType =
      widget.emi?.interest?.type ?? InterestType.reducingBalance;
  late InterestPeriod _interestPeriod =
      widget.emi?.interest?.period ?? InterestPeriod.yearly;
  late EmiLoanType _loanType = widget.emi?.loanType ?? EmiLoanType.other;

  /// "Link to Credit Card" — off by default; the card controls only appear
  /// once it's on. An existing card-linked EMI opens with it on.
  late bool _linkToCard = widget.emi?.linkedCreditCardId != null;
  _CardEmiKind _cardEmiKind = _CardEmiKind.productPurchase;
  late String? _linkedCreditCardId = widget.emi?.linkedCreditCardId;
  late String? _purchaseTransactionId = widget.emi?.purchaseTransactionId;
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
        installmentsPerYear: _installmentsPerYearFor(_installmentFrequency),
      );
      return (
        totalPayable: breakdown.totalPayable,
        totalInterest: breakdown.totalInterest,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mirrors `EmiRepository._installmentsPerYearFor` exactly, so this
  /// preview always matches what `createEmi`/`editEmiTerms` will actually
  /// persist — weekly gets its true per-year count (52) instead of being
  /// forced through the monthly bucket.
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

  int? get _parsedDueDayOfMonth =>
      int.tryParse(_dueDayOfMonthController.text.trim());

  /// Whether First EMI Date differs from [widget.emi]'s current [Emi.startDate]
  /// — only meaningful while editing, and only ever actionable when the form
  /// itself allowed the field to be tapped (i.e. no payments recorded yet).
  bool get _startDateChanged {
    final emi = widget.emi;
    if (emi == null) return false;
    return !_startDate.isAtSameMomentAs(emi.startDate);
  }

  /// "Card Name •••• 1234" — appends the last 4 digits (when set) so
  /// otherwise-identically-named cards are distinguishable in the linked
  /// card dropdown, matching the "•••• 1234" format used on the Credit
  /// Cards list/detail screens.
  String _cardLabel(
    CreditCardProfile card,
    Map<String, String> accountNameById,
  ) {
    final name = accountNameById[card.accountId] ?? 'Card';
    if (card.lastFourDigits != null && card.lastFourDigits!.isNotEmpty) {
      return '$name •••• ${card.lastFourDigits}';
    }
    return name;
  }

  /// "Original card purchase" — sets `Emi.purchaseTransactionId` to a
  /// purchase the user explicitly picks from this card's own transactions
  /// (never matched automatically by amount/date). Linking it tells FlowFi the
  /// purchase is already in the card's balance, so the EMI doesn't lock the
  /// same money again; "Not recorded" keeps the EMI as the card exposure.
  Widget _purchasePicker(BuildContext context, String cardId) {
    final purchases = [
      ...ref
          .watch(transactionsForCardProvider(cardId))
          .where((t) => t.type == TransactionType.expense),
    ]..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final localizations = MaterialLocalizations.of(context);
    final linkedMissing =
        _purchaseTransactionId != null &&
        purchases.every((t) => t.id != _purchaseTransactionId);
    return DropdownButtonFormField<String?>(
      key: ValueKey('purchase-$cardId'),
      initialValue: _purchaseTransactionId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Original card purchase (optional)',
        helperText:
            'Pick it if the purchase is already recorded on this card, so it '
            "isn't counted twice",
        helperMaxLines: 2,
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Not recorded on this card'),
        ),
        if (linkedMissing)
          DropdownMenuItem<String?>(
            value: _purchaseTransactionId,
            child: const Text('Linked purchase (no longer on this card)'),
          ),
        for (final t in purchases)
          DropdownMenuItem<String?>(
            value: t.id,
            child: Text(
              '${localizations.formatShortDate(t.dateTime)} · '
              '${t.description.isEmpty ? 'Purchase' : t.description} · '
              '${CurrencyFormatter.instance.format(t.amount)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) => setState(() => _purchaseTransactionId = value),
    );
  }

  /// "Link to Credit Card" — off by default. Only existing FlowFi cards are
  /// offered (closed/cancelled ones excluded, same as Web); new cards are
  /// added in Credit Cards, never inline here. While editing, the card this
  /// EMI is already linked to stays listed even if it has since closed.
  Widget _creditCardSection(BuildContext context) {
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final accountNameById = {for (final a in accounts) a.id: a.name};
    final eligibleCards = [
      for (final card in creditCards)
        if ((card.status != CreditCardStatus.closed &&
                card.status != CreditCardStatus.cancelled) ||
            card.id == widget.emi?.linkedCreditCardId)
          card,
    ];
    final hint = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: loanEmiSecondaryText(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...[
          if (eligibleCards.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No credit cards yet — add one, then come back.',
                    style: hint,
                  ),
                ),
                const AddElsewhereLink(
                  route: AppRoutes.creditCards,
                  label: 'Go to Credit Cards',
                ),
              ],
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue:
                  eligibleCards.any((c) => c.id == _linkedCreditCardId)
                  ? _linkedCreditCardId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Credit card'),
              hint: const Text('Select a card'),
              items: [
                for (final card in eligibleCards)
                  DropdownMenuItem<String>(
                    value: card.id,
                    child: Text(
                      _cardLabel(card, accountNameById),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _linkedCreditCardId = value;
                // A purchase belongs to one card — changing the card drops it.
                _purchaseTransactionId = null;
              }),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: AddElsewhereLink(
                route: AppRoutes.creditCards,
                label: 'Add Credit Card',
              ),
            ),
            if (!_isEditing) ...[
              const LoanEmiFieldLabel('What kind?'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_CardEmiKind>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _CardEmiKind.productPurchase,
                      label: Text('Purchase on EMI'),
                    ),
                    ButtonSegment(
                      value: _CardEmiKind.creditCardLoan,
                      label: Text('Loan on card'),
                    ),
                  ],
                  selected: {_cardEmiKind},
                  onSelectionChanged: (selection) =>
                      setState(() => _cardEmiKind = selection.first),
                ),
              ),
            ],
            if (_linkedCreditCardId != null) ...[
              const SizedBox(height: AppSizes.md),
              _purchasePicker(context, _linkedCreditCardId!),
            ],
            const SizedBox(height: AppSizes.sm),
            Text(
              "The amount is held against this card's limit and released "
              'as you pay it down.',
              style: hint,
            ),
          ],
        ],
      ],
    );
  }

  Future<bool> _confirmStartDateChange() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change First EMI Date?'),
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
    if (_linkToCard && _linkedCreditCardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Choose the card this EMI is on, or turn off \"It's on a credit card\"",
          ),
        ),
      );
      return;
    }
    // Off means unlinked, whatever card was picked before switching it off.
    final linkedCreditCardId = _linkToCard ? _linkedCreditCardId : null;
    final purchaseTransactionId = linkedCreditCardId == null
        ? null
        : _purchaseTransactionId;

    if (_isEditing && _startDateChanged) {
      final confirmed = await _confirmStartDateChange();
      if (!confirmed) return;
    }

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
          lenderName: _lenderController.text.trim().isEmpty
              ? null
              : _lenderController.text.trim(),
          categoryId: _categoryId,
          principalAmount: double.parse(_amountController.text.trim()),
          notes: _notesController.text.trim(),
          loanNumber: _loanNumberController.text.trim().isEmpty
              ? null
              : _loanNumberController.text.trim(),
          loanType: _loanType,
          branch: _branchController.text.trim().isEmpty
              ? null
              : _branchController.text.trim(),
          customerId: _customerIdController.text.trim().isEmpty
              ? null
              : _customerIdController.text.trim(),
          sanctionDate: _sanctionDate,
          disbursementDate: _disbursementDate,
          processingFee:
              _parseOptionalAmount(_processingFeeController.text) ?? 0,
          insuranceAmount: _parseOptionalAmount(_insuranceController.text) ?? 0,
          extraCharges: _parseOptionalAmount(_extraChargesController.text) ?? 0,
          foreclosureAmount: _parseOptionalAmount(_foreclosureController.text),
          prepaymentCharges: _parseOptionalAmount(
            _prepaymentChargesController.text,
          ),
          isAutoDebitEnabled: _isAutoDebitEnabled,
          autoDebitAccount:
              _isAutoDebitEnabled &&
                  _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
          linkedCreditCardId: linkedCreditCardId,
          clearLinkedCreditCardId: linkedCreditCardId == null,
          purchaseTransactionId: purchaseTransactionId,
          clearPurchaseTransactionId: purchaseTransactionId == null,
        );
        if (_startDateChanged) {
          final installments =
              ref.read(installmentsStreamProvider(emi.scheduleId)).value ??
              const [];
          await repository.editStartDate(
            emi,
            newStartDate: _startDate,
            hasPayments: hasPayments,
            currentInstallments: installments,
          );
        }
        if (_termsChanged) {
          final installments =
              ref.read(installmentsStreamProvider(emi.scheduleId)).value ??
              const [];
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
            newInstallmentCount: int.parse(
              _installmentCountController.text.trim(),
            ),
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
          lenderName: _lenderController.text.trim().isEmpty
              ? null
              : _lenderController.text.trim(),
          categoryId: _categoryId,
          interest: _hasInterest
              ? EmiInterest(
                  type: _interestType,
                  ratePercent: double.parse(_rateController.text.trim()),
                  period: _interestPeriod,
                )
              : null,
          notes: _notesController.text.trim(),
          loanNumber: _loanNumberController.text.trim().isEmpty
              ? null
              : _loanNumberController.text.trim(),
          // A card-linked EMI is recorded as a credit-card EMI, same as Web.
          loanType: linkedCreditCardId != null
              ? EmiLoanType.creditCard
              : _loanType,
          branch: _branchController.text.trim().isEmpty
              ? null
              : _branchController.text.trim(),
          customerId: _customerIdController.text.trim().isEmpty
              ? null
              : _customerIdController.text.trim(),
          sanctionDate: _sanctionDate,
          disbursementDate: _disbursementDate,
          processingFee:
              _parseOptionalAmount(_processingFeeController.text) ?? 0,
          insuranceAmount: _parseOptionalAmount(_insuranceController.text) ?? 0,
          extraCharges: _parseOptionalAmount(_extraChargesController.text) ?? 0,
          foreclosureAmount: _parseOptionalAmount(_foreclosureController.text),
          prepaymentCharges: _parseOptionalAmount(
            _prepaymentChargesController.text,
          ),
          isAutoDebitEnabled: _isAutoDebitEnabled,
          autoDebitAccount:
              _isAutoDebitEnabled &&
                  _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
          linkedCreditCardId: linkedCreditCardId,
          purchaseTransactionId: purchaseTransactionId,
          dueDayOfMonth: _parsedDueDayOfMonth,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save EMI: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(activeCategoriesProvider);
    final preview = _preview;
    final hasPayments = _isEditing
        ? ref.watch(emiTotalPaidProvider(widget.emi!)) > 0
        : false;
    final secondary = loanEmiSecondaryText(context);
    String formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _isEditing ? 'Edit EMI' : 'Add an EMI',
        confirmLabel: _isEditing ? 'Save changes' : 'Add EMI',
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1 — what it is and how much.
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "What's this EMI for?",
                hintText: 'e.g. iPhone 16, Sofa, Car',
              ),
              textInputAction: TextInputAction.next,
              validator: Validators.required,
            ),
            const SizedBox(height: AppSizes.md),
            TextFormField(
              controller: _amountController,
              enabled: !hasPayments,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Amount on EMI',
                prefixText: '₹ ',
                helperText: hasPayments
                    ? 'Amount can\'t be changed after a payment has been recorded'
                    : 'The amount being paid off in installments',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.amount,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSizes.md),

            // 2 — schedule.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _installmentCountController,
                    decoration: InputDecoration(
                      labelText: 'Installments',
                      hintText: 'e.g. 12',
                      helperText: _isEditing
                          ? 'Not less than already paid'
                          : null,
                    ),
                    keyboardType: TextInputType.number,
                    validator: Validators.required,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: DropdownButtonFormField<ScheduleType>(
                    initialValue: _installmentFrequency,
                    decoration: const InputDecoration(labelText: 'Paid'),
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
                      () =>
                          _installmentFrequency = value ?? ScheduleType.monthly,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !hasPayments,
              title: const Text('First EMI date'),
              subtitle: Text(formatDate(_startDate)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: hasPayments ? null : _pickStartDate,
            ),
            if (hasPayments)
              Padding(
                padding: const EdgeInsets.only(top: AppSizes.xs),
                child: Text(
                  'First EMI date can\'t be changed after a payment has been recorded',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ),
            const SizedBox(height: AppSizes.md),

            // 3 — credit card controls stay hidden until switched on.
            LoanEmiRevealSwitch(
              value: _linkToCard,
              onChanged: (value) => setState(() => _linkToCard = value),
              title: "It's on a credit card",
              subtitle:
                  "Credit Card EMI — the amount is held against the card's "
                  'limit and released as you pay.',
              children: [_creditCardSection(context)],
            ),
            const SizedBox(height: AppSizes.md),

            // 4 — interest, only when there is some.
            LoanEmiRevealSwitch(
              value: _hasInterest,
              onChanged: (value) => setState(() => _hasInterest = value),
              title: 'It has interest',
              subtitle: 'Leave off for a no-cost EMI.',
              children: [
                TextFormField(
                  controller: _rateController,
                  decoration: InputDecoration(
                    labelText: 'Interest rate (%)',
                    helperText: _interestPeriod == InterestPeriod.yearly
                        ? 'The yearly rate your bank quotes, e.g. 15.12'
                        : 'The rate charged per month',
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
                  Container(
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
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
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSizes.md),

            // 5 — everything optional.
            LoanEmiMoreOptions(
              initiallyExpanded: _isEditing,
              summary: 'Lender, type, due day, bank details, charges, notes',
              children: [
                TextFormField(
                  controller: _lenderController,
                  decoration: const InputDecoration(
                    labelText: 'Lender / store',
                    hintText: 'e.g. Bajaj Finance, HDFC Bank',
                  ),
                ),
                // A new card-linked EMI is always a credit-card EMI (see
                // _save), so the type only shows when it's actually a choice.
                if (_isEditing || !_linkToCard) ...[
                  const SizedBox(height: AppSizes.md),
                  DropdownButtonFormField<EmiLoanType>(
                    initialValue: _loanType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final type in EmiLoanType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (value) =>
                        setState(() => _loanType = value ?? EmiLoanType.other),
                  ),
                ],
                const SizedBox(height: AppSizes.md),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                if (_installmentFrequency == ScheduleType.monthly) ...[
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _dueDayOfMonthController,
                    decoration: const InputDecoration(
                      labelText: 'Monthly due day',
                      helperText:
                          'The fixed day every EMI after the first is due on, e.g. 5 for the 5th',
                      helperMaxLines: 2,
                      suffixText: 'day of month',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return null;
                      final day = int.tryParse(trimmed);
                      if (day == null || day < 1 || day > 31) {
                        return 'Enter a day between 1 and 31';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                ExpansionTile(
                  title: const Text('Bank details'),
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  initiallyExpanded: _showBankDetails,
                  onExpansionChanged: (expanded) =>
                      setState(() => _showBankDetails = expanded),
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    TextFormField(
                      controller: _loanNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Loan / account number',
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    TextFormField(
                      controller: _branchController,
                      decoration: const InputDecoration(labelText: 'Branch'),
                    ),
                    const SizedBox(height: AppSizes.md),
                    TextFormField(
                      controller: _customerIdController,
                      decoration: const InputDecoration(
                        labelText: 'Customer ID',
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sanction date'),
                      subtitle: Text(
                        _sanctionDate == null
                            ? 'Not set'
                            : formatDate(_sanctionDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _pickSanctionDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Loan disbursement date'),
                      subtitle: Text(
                        _disbursementDate == null
                            ? 'Not set'
                            : formatDate(_disbursementDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _pickDisbursementDate,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto debit enabled'),
                      subtitle: const Text(
                        'For your reference only — this app does not process payments',
                      ),
                      value: _isAutoDebitEnabled,
                      onChanged: (value) =>
                          setState(() => _isAutoDebitEnabled = value),
                    ),
                    if (_isAutoDebitEnabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.md),
                        child: TextFormField(
                          controller: _autoDebitAccountController,
                          decoration: const InputDecoration(
                            labelText: 'Auto debit account',
                          ),
                        ),
                      ),
                  ],
                ),
                ExpansionTile(
                  title: const Text('Fees & charges'),
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  initiallyExpanded: _showCharges,
                  onExpansionChanged: (expanded) =>
                      setState(() => _showCharges = expanded),
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    for (final (controller, label) in [
                      (_processingFeeController, 'Processing fee'),
                      (_insuranceController, 'Insurance amount'),
                      (_extraChargesController, 'Other charges'),
                      (_foreclosureController, 'Foreclosure amount'),
                      (_prepaymentChargesController, 'Prepayment charges'),
                    ]) ...[
                      TextFormField(
                        controller: controller,
                        decoration: InputDecoration(labelText: label),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: AppSizes.md),
                    ],
                  ],
                ),
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
}
