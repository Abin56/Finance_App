import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/dialogs/expense_guardrail_dialogs.dart';
import '../../domain/expense.dart';
import '../../domain/expense_participant.dart';
import '../providers/expense_providers.dart';

/// Whether an Add Payment save is a partial pre-payment (doesn't close the
/// expense regardless of amount) or an attempt to collect everything owed —
/// the Figma "Add Payment" screen's segmented toggle.
enum _PaymentType { advance, settle }

/// Figma "Add Payment" (frame 4) — a Cancel/Save modal for collecting one
/// split-expense participant's payment toward their share, scoped to a
/// single [participant]/[installment] pair. Saves via
/// [ExpenseRepository.settleParticipant], which records the
/// `InstallmentPayment` *and* reverses the participant's person `LedgerEntry`
/// in one call — both must happen together or the person's balance and their
/// installment status silently disagree.
class RecordSplitPaymentSheet extends ConsumerStatefulWidget {
  const RecordSplitPaymentSheet({
    super.key,
    required this.expense,
    required this.participant,
    required this.installment,
  });

  final Expense expense;
  final ExpenseParticipant participant;
  final Installment installment;

  /// Resolves to `true` only when a payment was recorded, so callers show a
  /// success confirmation only on an actual save (not on cancel/back).
  static Future<bool?> show(
    BuildContext context, {
    required Expense expense,
    required ExpenseParticipant participant,
    required Installment installment,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RecordSplitPaymentSheet(expense: expense, participant: participant, installment: installment),
      ),
    );
  }

  @override
  ConsumerState<RecordSplitPaymentSheet> createState() => _RecordSplitPaymentSheetState();
}

class _RecordSplitPaymentSheetState extends ConsumerState<RecordSplitPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: widget.installment.remainingAmount.toStringAsFixed(2),
  );
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  _PaymentType _type = _PaymentType.advance;

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

  void _onTypeChanged(Set<_PaymentType> selection) {
    setState(() {
      _type = selection.first;
      if (_type == _PaymentType.settle) {
        _amountController.text = widget.installment.remainingAmount.toStringAsFixed(2);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final amount = double.parse(_amountController.text.trim());
      await ref.read(expenseRepositoryProvider).settleParticipant(
            expense: widget.expense,
            participant: widget.participant,
            installment: widget.installment,
            installmentPaymentRepository: ref.read(
              installmentPaymentRepositoryProvider(
                (scheduleId: widget.installment.scheduleId, installmentId: widget.installment.id),
              ),
            ),
            amount: amount,
            date: _date,
            note: _noteController.text.trim(),
          );
      if (!mounted) return;

      final remaining = (widget.installment.remainingAmount - amount).clamp(0.0, widget.installment.remainingAmount);
      if (remaining > 0) {
        // Shown while this modal's own context is still valid — safer than
        // popping first and reusing a context whose route is mid-removal.
        await showPartialPaymentInfo(context, remainingAmount: remaining);
      }
      if (mounted) Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        leadingWidth: 80,
        title: const Text('Add Payment'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text('Save', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            AppCard(
              child: Column(
                children: [
                  _RecapRow(label: 'Total Amount', value: widget.participant.share),
                  const SizedBox(height: AppSizes.sm),
                  _RecapRow(label: 'Remaining', value: widget.installment.remainingAmount),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Payment Type', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.sm),
            SegmentedButton<_PaymentType>(
              segments: const [
                ButtonSegment(value: _PaymentType.advance, label: Text('Advance')),
                ButtonSegment(value: _PaymentType.settle, label: Text('Settle')),
              ],
              selected: {_type},
              onSelectionChanged: _onTypeChanged,
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Amount', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSizes.xs),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee_rounded)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.amount,
              readOnly: _type == _PaymentType.settle,
            ),
            const SizedBox(height: AppSizes.md),
            Text('Date', style: context.textTheme.titleSmall),
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
            if (_type == _PaymentType.advance) ...[
              const SizedBox(height: AppSizes.md),
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
                    Expanded(
                      child: Text(
                        "This is an advance payment. You will still see the remaining amount until it's settled.",
                        style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
