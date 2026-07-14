import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/dialogs/expense_guardrail_dialogs.dart';
import '../../domain/expense.dart';
import '../../domain/expense_participant.dart';
import '../providers/expense_providers.dart';

/// Figma "Settle Amount" (frame 6) — a Cancel/Settle modal that closes out
/// one split-expense participant's remaining balance. Distinct from
/// [RecordSplitPaymentSheet] (Add Payment's general-purpose Advance/Settle
/// toggle): this always zeroes out [Installment.remainingAmount], shows the
/// fuller Total/Paid/Remaining recap plus an explicit "I have received the
/// full amount" toggle, and is guarded so it can't silently under-collect.
/// Saves via the same [ExpenseRepository.settleParticipant] call, so both
/// surfaces keep the person's ledger and the installment in sync the same way.
class SettleAmountSheet extends ConsumerStatefulWidget {
  const SettleAmountSheet({
    super.key,
    required this.expense,
    required this.participant,
    required this.installment,
  });

  final Expense expense;
  final ExpenseParticipant participant;
  final Installment installment;

  /// Resolves to `true` only when the amount was settled, so callers show a
  /// success confirmation only on an actual settle (not on cancel/back).
  static Future<bool?> show(
    BuildContext context, {
    required Expense expense,
    required ExpenseParticipant participant,
    required Installment installment,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SettleAmountSheet(expense: expense, participant: participant, installment: installment),
      ),
    );
  }

  @override
  ConsumerState<SettleAmountSheet> createState() => _SettleAmountSheetState();
}

class _SettleAmountSheetState extends ConsumerState<SettleAmountSheet> {
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _receivedFullAmount = true;
  bool _isSaving = false;

  @override
  void dispose() {
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

  Future<void> _settle() async {
    if (!_receivedFullAmount) {
      await showCannotSettleInfo(context, remainingAmount: widget.installment.remainingAmount);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(expenseRepositoryProvider).settleParticipant(
            expense: widget.expense,
            participant: widget.participant,
            installment: widget.installment,
            installmentPaymentRepository: ref.read(
              installmentPaymentRepositoryProvider(
                (scheduleId: widget.installment.scheduleId, installmentId: widget.installment.id),
              ),
            ),
            amount: widget.installment.remainingAmount,
            date: _date,
            note: _noteController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not settle: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final installment = widget.installment;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        leadingWidth: 80,
        title: const Text('Settle Amount'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _settle,
            child: Text('Settle', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          AppCard(
            child: Column(
              children: [
                _RecapRow(label: 'Total Amount', value: widget.participant.share),
                const SizedBox(height: AppSizes.sm),
                _RecapRow(label: 'Paid', value: installment.amountPaid),
                const SizedBox(height: AppSizes.sm),
                _RecapRow(label: 'Remaining', value: installment.remainingAmount, valueColor: AppColors.error),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: AppSizes.iconSm, color: context.colors.primary),
                const SizedBox(width: AppSizes.sm),
                const Expanded(child: Text('You are about to mark this expense as fully settled.')),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Payment Date', style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.xs),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            child: InputDecorator(
              decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined)),
              child: Text(_date.fullDate),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text('Note (Optional)', style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.xs),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(),
            maxLines: 2,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSizes.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I have received the full amount'),
            value: _receivedFullAmount,
            onChanged: (value) => setState(() => _receivedFullAmount = value),
          ),
          const SizedBox(height: AppSizes.sm),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'This expense will be marked as',
                  style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7)),
                ),
                _OutcomePill(settled: _receivedFullAmount),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({required this.label, required this.value, this.valueColor});

  final String label;
  final double value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
        ),
      ],
    );
  }
}

class _OutcomePill extends StatelessWidget {
  const _OutcomePill({required this.settled});

  final bool settled;

  @override
  Widget build(BuildContext context) {
    final color = settled ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
      child: Text(
        settled ? 'Settled ✓' : 'Partly Paid',
        style: context.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
