import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../expense/presentation/widgets/record_split_payment_sheet.dart';
import '../../domain/person.dart';
import '../providers/person_pending_participants_providers.dart';

/// Which pending amount a payment is being recorded against — the three
/// choices "Receive Money" offers so the user isn't forced to hunt through
/// a generic form for the common "just clear everything" case.
enum _PaymentTarget { allPending, specificExpense, customAmount }

/// "Rahul gave me money — record it" — renamed/redesigned from the old
/// one-button "Record payment" sheet per Milestone 15. Three payment-target
/// paths, all routed through existing settlement machinery:
/// - All pending amount / Custom amount: both fan out across the person's
///   outstanding split/assigned-expense installments oldest-due-first via
///   [ExpenseRepository.settleAcrossPending], so every dollar produces a
///   traceable `InstallmentPayment` per expense instead of one
///   undifferentiated ledger entry. Only a remainder beyond total tracked
///   pending (e.g. an untracked manual-lending balance) still posts as a
///   plain ledger entry.
/// - Specific expense: delegates entirely to [RecordSplitPaymentSheet] for
///   the chosen participant/installment — no settlement math duplicated here.
class SettleUpSheet extends ConsumerStatefulWidget {
  const SettleUpSheet({super.key, required this.person});

  final Person person;

  static Future<void> show(BuildContext context, Person person) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettleUpSheet(person: person),
    );
  }

  @override
  ConsumerState<SettleUpSheet> createState() => _SettleUpSheetState();
}

class _SettleUpSheetState extends ConsumerState<SettleUpSheet> {
  final _formKey = GlobalKey<FormState>();
  _PaymentTarget _target = _PaymentTarget.allPending;
  late final _amountController = TextEditingController(text: widget.person.currentBalance.abs().toStringAsFixed(2));
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
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

  Future<void> _saveAllPendingOrCustom({required double amount, required DateTime date, required String note}) async {
    setState(() => _isSaving = true);
    try {
      final pending = ref.read(personSplitParticipantsProvider(widget.person.id)).where(
            (p) => p.installment.remainingAmount > 0,
          ).toList()
        ..sort((a, b) => a.installment.dueDate.compareTo(b.installment.dueDate));

      await ref.read(expenseRepositoryProvider).settleAcrossPending(
            person: widget.person,
            pending: pending,
            amount: amount,
            date: date,
            installmentPaymentRepositoryFor: (scheduleId, installmentId) => ref.read(
              installmentPaymentRepositoryProvider((scheduleId: scheduleId, installmentId: installmentId)),
            ),
            note: note.isEmpty ? 'Payment recorded' : note,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record payment: $e')));
      }
    }
  }

  void _pickSpecificExpense(PendingSplitParticipant participant) {
    Navigator.of(context).pop();
    RecordSplitPaymentSheet.show(
      context,
      expense: participant.expense,
      participant: participant.participant,
      installment: participant.installment,
    );
  }

  Future<void> _save() async {
    if (widget.person.currentBalance == 0) return;
    switch (_target) {
      case _PaymentTarget.allPending:
        await _saveAllPendingOrCustom(
          amount: widget.person.currentBalance.abs(),
          date: DateTime.now(),
          note: '',
        );
      case _PaymentTarget.specificExpense:
        return; // Handled by tapping a row directly — no button action.
      case _PaymentTarget.customAmount:
        if (!_formKey.currentState!.validate()) return;
        await _saveAllPendingOrCustom(
          amount: double.parse(_amountController.text.trim()),
          date: _date,
          note: _noteController.text.trim(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final amount = CurrencyFormatter.instance.format(person.currentBalance.abs());
    final pendingParticipants = ref
        .watch(personSplitParticipantsProvider(person.id))
        .where((p) => p.installment.remainingAmount > 0)
        .toList();

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
              Text('Receive Money from ${person.name}', style: context.textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              if (person.currentBalance == 0)
                Text(
                  'Nothing to receive — you\'re all paid up.',
                  style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Text(
                    'When ${person.name} gives you money, save it here. This automatically reduces the remaining amount.',
                    style: context.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                Text('Select which payment is this for?', style: context.textTheme.titleSmall),
                const SizedBox(height: AppSizes.xs),
                RadioGroup<_PaymentTarget>(
                  groupValue: _target,
                  onChanged: (value) => setState(() => _target = value!),
                  child: Column(
                    children: [
                      RadioListTile<_PaymentTarget>(
                        contentPadding: EdgeInsets.zero,
                        value: _PaymentTarget.allPending,
                        title: Text('All pending amount ($amount)'),
                      ),
                      RadioListTile<_PaymentTarget>(
                        contentPadding: EdgeInsets.zero,
                        value: _PaymentTarget.specificExpense,
                        title: const Text('Specific expense'),
                        enabled: pendingParticipants.isNotEmpty,
                      ),
                      RadioListTile<_PaymentTarget>(
                        contentPadding: EdgeInsets.zero,
                        value: _PaymentTarget.customAmount,
                        title: const Text('Custom amount'),
                      ),
                    ],
                  ),
                ),
                if (_target == _PaymentTarget.specificExpense) ...[
                  const SizedBox(height: AppSizes.sm),
                  if (pendingParticipants.isEmpty)
                    const Text('No pending expenses for this person.')
                  else
                    for (final participant in pendingParticipants)
                      Card(
                        margin: const EdgeInsets.only(bottom: AppSizes.xs),
                        child: ListTile(
                          title: Text(participant.expense.description),
                          subtitle: Text(CurrencyFormatter.instance.format(participant.installment.remainingAmount)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _pickSpecificExpense(participant),
                        ),
                      ),
                ],
                if (_target == _PaymentTarget.customAmount) ...[
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(labelText: 'Amount Received'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: Validators.amount,
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
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                  ),
                ],
                const SizedBox(height: AppSizes.lg),
                if (_target != _PaymentTarget.specificExpense)
                  PrimaryButton(label: 'Save Payment', isLoading: _isSaving, onPressed: _save),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'After saving, ${person.name}\'s pending amount will be updated automatically.',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                ),
              ],
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
