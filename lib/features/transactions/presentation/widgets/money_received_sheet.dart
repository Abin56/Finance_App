import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/models/receipt_purpose.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/services/providers/receipt_classification_providers.dart';
import '../../../../core/services/receipt_classification_router.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/domain/emi.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/domain/loan.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../savings/domain/savings_goal.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
import '../../../transactions/domain/transaction_type.dart';

/// Bottom sheet for recording money that came in, classified by *why* it
/// arrived (`ReceiptPurpose`) rather than being just another income
/// transaction. Every purpose is shown in plain language; picking one that
/// settles against something specific (a person, a loan/EMI installment, a
/// savings goal, a split expense participant) reveals only the picker that
/// purpose actually needs, then
/// `ReceiptClassificationRouter.classify` does the rest — this sheet never
/// hand-rolls the ledger/installment/savings side effects itself.
class MoneyReceivedSheet extends ConsumerStatefulWidget {
  const MoneyReceivedSheet({super.key, this.smsPrefill});

  /// Set when opened from the SMS Inbox's "Someone Paid Me" option — seeds
  /// amount/date/account/category as normal editable initial values.
  /// `purpose` is deliberately left for the user to pick: an SMS can tell
  /// you money arrived, never *why*, and guessing wrong here would silently
  /// misroute a ledger/installment/savings side effect.
  final SmsPrefill? smsPrefill;

  static Future<void> show(BuildContext context, {SmsPrefill? smsPrefill}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => MoneyReceivedSheet(smsPrefill: smsPrefill),
    );
  }

  @override
  ConsumerState<MoneyReceivedSheet> createState() => _MoneyReceivedSheetState();
}

class _MoneyReceivedSheetState extends ConsumerState<MoneyReceivedSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: widget.smsPrefill == null ? '' : widget.smsPrefill!.amount.toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(text: widget.smsPrefill?.note ?? '');
  late DateTime _date = widget.smsPrefill?.dateTime ?? DateTime.now();
  ReceiptPurpose? _purpose;
  late String? _accountId = widget.smsPrefill?.suggestedAccountId;
  late String? _categoryId = widget.smsPrefill?.suggestedCategoryId;
  String? _personId;
  String? _loanId;
  String? _emiId;
  String? _installmentId;
  String? _savingsGoalId;
  String? _splitParticipantKey;

  String? _purposeError;
  String? _accountError;
  String? _categoryError;
  String? _targetError;
  bool _isSaving = false;

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

  void _resetTargetSelections() {
    _personId = null;
    _loanId = null;
    _emiId = null;
    _installmentId = null;
    _savingsGoalId = null;
    _splitParticipantKey = null;
    _targetError = null;
  }

  Future<void> _save({
    required List<Person> people,
    required List<Loan> loans,
    required List<Emi> emis,
    required List<SavingsGoal> savingsGoals,
    required List<Installment> targetInstallments,
    required List<PendingSplitParticipant> pendingSplitParticipants,
  }) async {
    final formValid = _formKey.currentState!.validate();
    final purpose = _purpose;
    setState(() {
      _purposeError = purpose == null ? 'Choose why you received this money' : null;
      _accountError = _accountId == null ? 'Select an account' : null;
      _categoryError = _categoryId == null ? 'Select a category' : null;
      _targetError = _validateTargetSelection(purpose);
    });
    if (!formValid || purpose == null || _accountId == null || _categoryId == null || _targetError != null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final target = _buildTarget(
        purpose: purpose,
        people: people,
        loans: loans,
        emis: emis,
        savingsGoals: savingsGoals,
        targetInstallments: targetInstallments,
        pendingSplitParticipants: pendingSplitParticipants,
      );
      final transaction = await ref.read(receiptClassificationRouterProvider).classify(
            purpose: purpose,
            amount: double.parse(_amountController.text.trim()),
            date: _date,
            accountId: _accountId!,
            categoryId: _categoryId!,
            target: target,
            note: _noteController.text.trim(),
            source: widget.smsPrefill == null ? null : 'sms',
          );

      await completeSmsImport(ref, smsPrefill: widget.smsPrefill, linkedEntityId: transaction.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  /// Plain-language validation for the conditional target picker(s), before
  /// even calling the router (which would also reject a missing target, but
  /// with a less specific message tied to field names rather than the UI).
  String? _validateTargetSelection(ReceiptPurpose? purpose) {
    if (purpose == null) return null;
    switch (purpose.targetKind) {
      case ReceiptTargetKind.person:
        return _personId == null ? 'Select who returned the money' : null;
      case ReceiptTargetKind.loanInstallment:
        if (_loanId == null) return 'Select which loan this pays off';
        return _installmentId == null ? 'Select which payment this is for' : null;
      case ReceiptTargetKind.emiInstallment:
        if (_emiId == null) return 'Select which EMI this pays off';
        return _installmentId == null ? 'Select which payment this is for' : null;
      case ReceiptTargetKind.savingsGoal:
        return _savingsGoalId == null ? 'Select which savings goal this adds to' : null;
      case ReceiptTargetKind.splitExpenseParticipant:
        return _splitParticipantKey == null ? 'Select which shared expense this pays' : null;
      case ReceiptTargetKind.none:
        return null;
    }
  }

  ReceiptClassificationTarget _buildTarget({
    required ReceiptPurpose purpose,
    required List<Person> people,
    required List<Loan> loans,
    required List<Emi> emis,
    required List<SavingsGoal> savingsGoals,
    required List<Installment> targetInstallments,
    required List<PendingSplitParticipant> pendingSplitParticipants,
  }) {
    switch (purpose.targetKind) {
      case ReceiptTargetKind.person:
        final person = people.firstWhere((p) => p.id == _personId);
        return ReceiptClassificationTarget(person: person);

      case ReceiptTargetKind.loanInstallment:
        final loan = loans.firstWhere((l) => l.id == _loanId);
        // Institutional loans have no linked person — `person` stays null
        // for them, and `ReceiptClassificationRouter` skips the ledger
        // update accordingly instead of requiring one.
        final person = loan.personId == null ? null : people.firstWhereOrNull((p) => p.id == loan.personId);
        final installment = targetInstallments.firstWhere((i) => i.id == _installmentId);
        return ReceiptClassificationTarget(
          loan: loan,
          person: person,
          installment: installment,
          installmentPaymentRepository: ref.read(
            installmentPaymentRepositoryProvider(
              (scheduleId: loan.scheduleId, installmentId: installment.id),
            ),
          ),
        );

      case ReceiptTargetKind.emiInstallment:
        final emi = emis.firstWhere((e) => e.id == _emiId);
        final installment = targetInstallments.firstWhere((i) => i.id == _installmentId);
        return ReceiptClassificationTarget(
          emi: emi,
          installment: installment,
          installmentPaymentRepository: ref.read(
            installmentPaymentRepositoryProvider(
              (scheduleId: emi.scheduleId, installmentId: installment.id),
            ),
          ),
        );

      case ReceiptTargetKind.savingsGoal:
        final goal = savingsGoals.firstWhere((g) => g.id == _savingsGoalId);
        return ReceiptClassificationTarget(
          savingsGoal: goal,
          savingsRepository: ref.read(savingsRepositoryProvider),
        );

      case ReceiptTargetKind.splitExpenseParticipant:
        final entry = pendingSplitParticipants.firstWhere(
          (e) => e.installment.id == _splitParticipantKey,
        );
        return ReceiptClassificationTarget(
          expense: entry.expense,
          expenseParticipant: entry.participant,
          installment: entry.installment,
          installmentPaymentRepository: ref.read(
            installmentPaymentRepositoryProvider(
              (scheduleId: entry.expense.scheduleId!, installmentId: entry.installment.id),
            ),
          ),
          expenseRepository: ref.read(expenseRepositoryProvider),
        );

      case ReceiptTargetKind.none:
        return const ReceiptClassificationTarget();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.income));
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final loans = ref.watch(activeLoansProvider);
    final emis = ref.watch(activeEmisProvider);
    final savingsGoals = ref.watch(activeSavingsGoalsProvider);
    final pendingSplitParticipants = ref.watch(pendingSplitParticipantsProvider);

    final purpose = _purpose;
    final selectedLoan = loans.where((l) => l.id == _loanId).firstOrNull;
    final selectedEmi = emis.where((e) => e.id == _emiId).firstOrNull;
    final loanInstallments =
        selectedLoan == null ? const <Installment>[] : ref.watch(installmentsStreamProvider(selectedLoan.scheduleId)).value ?? const [];
    final emiInstallments =
        selectedEmi == null ? const <Installment>[] : ref.watch(installmentsStreamProvider(selectedEmi.scheduleId)).value ?? const [];

    final unpaidLoanInstallments = loanInstallments.where((i) => i.remainingAmount > 0).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final unpaidEmiInstallments = emiInstallments.where((i) => i.remainingAmount > 0).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final targetInstallments = purpose?.targetKind == ReceiptTargetKind.loanInstallment
        ? unpaidLoanInstallments
        : purpose?.targetKind == ReceiptTargetKind.emiInstallment
            ? unpaidEmiInstallments
            : const <Installment>[];

    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: 'Money received',
        confirmLabel: 'Save',
        isSaving: _isSaving,
        onConfirm: () => _save(
          people: people,
          loans: loans,
          emis: emis,
          savingsGoals: savingsGoals,
          targetInstallments: targetInstallments,
          pendingSplitParticipants: pendingSplitParticipants,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              const SectionLabel('What & How Much'),
              const SizedBox(height: AppSizes.sm),
              DropdownButtonFormField<ReceiptPurpose>(
                initialValue: purpose,
                decoration: _premiumDecoration(context, label: 'Why did you receive this?', errorText: _purposeError),
                style: Theme.of(context).textTheme.bodyMedium,
                items: [
                  for (final p in ReceiptPurpose.values) DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (value) => setState(() {
                  _purpose = value;
                  _purposeError = null;
                  _resetTargetSelections();
                }),
              ),
              const SizedBox(height: AppSizes.sm),
              TextFormField(
                controller: _amountController,
                decoration: _premiumDecoration(context, label: 'Amount'),
                style: Theme.of(context).textTheme.bodyMedium,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              const SectionLabel('Where From'),
              const SizedBox(height: AppSizes.sm),
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load accounts: $error'),
                data: (allAccounts) {
                  final accounts = allAccounts.where((a) => a.type != AccountType.card).toList();
                  final validId = accounts.any((a) => a.id == _accountId) ? _accountId : null;
                  return DropdownButtonFormField<String>(
                    initialValue: validId,
                    decoration: _premiumDecoration(context, label: 'Account', errorText: _accountError),
                    style: Theme.of(context).textTheme.bodyMedium,
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(value: account.id, child: Text(accountPickerLabel(account, creditCards))),
                    ],
                    onChanged: (value) => setState(() {
                      _accountId = value;
                      _accountError = null;
                    }),
                  );
                },
              ),
              const SizedBox(height: AppSizes.sm),
              DropdownButtonFormField<String>(
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: _premiumDecoration(context, label: 'Category', errorText: _categoryError),
                style: Theme.of(context).textTheme.bodyMedium,
                items: [
                  for (final category in categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() {
                  _categoryId = value;
                  _categoryError = null;
                }),
              ),
              const SizedBox(height: AppSizes.sm),
              _PremiumTapButton(onTap: _pickDate, icon: Icons.calendar_today_outlined, label: _date.fullDate),
              if (purpose != null && purpose.targetKind != ReceiptTargetKind.none) ...[
                const SizedBox(height: AppSizes.md),
                const SectionLabel('Details'),
                const SizedBox(height: AppSizes.sm),
                ..._buildTargetFields(
                  purpose: purpose,
                  people: people,
                  loans: loans,
                  emis: emis,
                  savingsGoals: savingsGoals,
                  unpaidLoanInstallments: unpaidLoanInstallments,
                  unpaidEmiInstallments: unpaidEmiInstallments,
                  pendingSplitParticipants: pendingSplitParticipants,
                ),
              ],
              const SizedBox(height: AppSizes.md),
              const SectionLabel('Note'),
              const SizedBox(height: AppSizes.sm),
              TextFormField(
                controller: _noteController,
                decoration: _premiumDecoration(context, label: 'Note (optional)'),
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTargetFields({
    required ReceiptPurpose purpose,
    required List<Person> people,
    required List<Loan> loans,
    required List<Emi> emis,
    required List<SavingsGoal> savingsGoals,
    required List<Installment> unpaidLoanInstallments,
    required List<Installment> unpaidEmiInstallments,
    required List<PendingSplitParticipant> pendingSplitParticipants,
  }) {
    switch (purpose.targetKind) {
      case ReceiptTargetKind.person:
        return [
          DropdownButtonFormField<String>(
            initialValue: people.any((p) => p.id == _personId) ? _personId : null,
            decoration: _premiumDecoration(context, label: 'Who returned the money?', errorText: _targetError),
            style: Theme.of(context).textTheme.bodyMedium,
            items: [
              for (final person in people) DropdownMenuItem(value: person.id, child: Text(person.name)),
            ],
            onChanged: (value) => setState(() {
              _personId = value;
              _targetError = null;
            }),
          ),
        ];

      case ReceiptTargetKind.loanInstallment:
        return [
          DropdownButtonFormField<String>(
            initialValue: loans.any((l) => l.id == _loanId) ? _loanId : null,
            decoration: _premiumDecoration(context, label: 'Which loan is this for?', errorText: _targetError),
            style: Theme.of(context).textTheme.bodyMedium,
            items: [
              for (final loan in loans)
                DropdownMenuItem(
                  value: loan.id,
                  child: Text(loan.name?.isNotEmpty == true ? loan.name! : CurrencyFormatter.instance.format(loan.loanAmount)),
                ),
            ],
            onChanged: (value) => setState(() {
              _loanId = value;
              _installmentId = null;
              _targetError = null;
            }),
          ),
          if (_loanId != null) ...[
            const SizedBox(height: AppSizes.sm),
            DropdownButtonFormField<String>(
              initialValue: unpaidLoanInstallments.any((i) => i.id == _installmentId) ? _installmentId : null,
              decoration: _premiumDecoration(context, label: 'Which payment is this for?', errorText: _targetError),
              style: Theme.of(context).textTheme.bodyMedium,
              items: [
                for (final installment in unpaidLoanInstallments)
                  DropdownMenuItem(
                    value: installment.id,
                    child: Text(
                      '${installment.dueDate.fullDate} · ${CurrencyFormatter.instance.format(installment.remainingAmount)} left',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _installmentId = value;
                _targetError = null;
              }),
            ),
          ],
        ];

      case ReceiptTargetKind.emiInstallment:
        return [
          DropdownButtonFormField<String>(
            initialValue: emis.any((e) => e.id == _emiId) ? _emiId : null,
            decoration: _premiumDecoration(context, label: 'Which EMI is this for?', errorText: _targetError),
            style: Theme.of(context).textTheme.bodyMedium,
            items: [
              for (final emi in emis) DropdownMenuItem(value: emi.id, child: Text(emi.name)),
            ],
            onChanged: (value) => setState(() {
              _emiId = value;
              _installmentId = null;
              _targetError = null;
            }),
          ),
          if (_emiId != null) ...[
            const SizedBox(height: AppSizes.sm),
            DropdownButtonFormField<String>(
              initialValue: unpaidEmiInstallments.any((i) => i.id == _installmentId) ? _installmentId : null,
              decoration: _premiumDecoration(context, label: 'Which payment is this for?', errorText: _targetError),
              style: Theme.of(context).textTheme.bodyMedium,
              items: [
                for (final installment in unpaidEmiInstallments)
                  DropdownMenuItem(
                    value: installment.id,
                    child: Text(
                      '${installment.dueDate.fullDate} · ${CurrencyFormatter.instance.format(installment.remainingAmount)} left',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _installmentId = value;
                _targetError = null;
              }),
            ),
          ],
        ];

      case ReceiptTargetKind.savingsGoal:
        return [
          DropdownButtonFormField<String>(
            initialValue: savingsGoals.any((g) => g.id == _savingsGoalId) ? _savingsGoalId : null,
            decoration: _premiumDecoration(context, label: 'Which savings goal does this add to?', errorText: _targetError),
            style: Theme.of(context).textTheme.bodyMedium,
            items: [
              for (final goal in savingsGoals) DropdownMenuItem(value: goal.id, child: Text(goal.name)),
            ],
            onChanged: (value) => setState(() {
              _savingsGoalId = value;
              _targetError = null;
            }),
          ),
        ];

      case ReceiptTargetKind.splitExpenseParticipant:
        return [
          DropdownButtonFormField<String>(
            initialValue: pendingSplitParticipants.any((e) => e.installment.id == _splitParticipantKey)
                ? _splitParticipantKey
                : null,
            decoration: _premiumDecoration(context, label: 'Which shared expense is this for?', errorText: _targetError),
            style: Theme.of(context).textTheme.bodyMedium,
            items: [
              for (final entry in pendingSplitParticipants)
                DropdownMenuItem(
                  value: entry.installment.id,
                  child: Text(
                    '${entry.expense.description} — ${entry.participant.name} · '
                    '${CurrencyFormatter.instance.format(entry.installment.remainingAmount)} left',
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              _splitParticipantKey = value;
              _targetError = null;
            }),
          ),
        ];

      case ReceiptTargetKind.none:
        return const [];
    }
  }
}

/// The filled, borderless-until-focus field decoration every field on this
/// sheet shares — same vocabulary as `SplitExpenseFormSheet`'s
/// `_premiumDecoration`, so every "Add X" sheet in the app reads as one
/// consistent premium language.
InputDecoration _premiumDecoration(
  BuildContext context, {
  required String label,
  String? errorText,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
    filled: true,
    fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.6),
    ),
  );
}

/// A filled icon+label tap button — the premium replacement for
/// [OutlinedButton.icon], used for the date picker so it matches this
/// sheet's filled-field language instead of standing out as an outlined
/// control on its own.
class _PremiumTapButton extends StatelessWidget {
  const _PremiumTapButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSizes.iconSm, color: colors.primary),
              const SizedBox(width: AppSizes.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
