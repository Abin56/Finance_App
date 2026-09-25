import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/payment_schedule/domain/disbursement_reamortization_policy.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/prepayment_reamortization_policy.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/loan.dart';
import '../../domain/loan_adjustment_preview.dart';
import '../../domain/loan_direction.dart';
import '../providers/loan_providers.dart';

enum LoanAdjustmentKind { principalPrepayment, additionalDisbursement }

class LoanAdjustmentSheet extends ConsumerStatefulWidget {
  const LoanAdjustmentSheet({
    super.key,
    required this.loan,
    required this.installments,
    required this.kind,
  });
  final Loan loan;
  final List<Installment> installments;
  final LoanAdjustmentKind kind;

  static Future<void> show(
    BuildContext context, {
    required Loan loan,
    required List<Installment> installments,
    required LoanAdjustmentKind kind,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) =>
        LoanAdjustmentSheet(loan: loan, installments: installments, kind: kind),
  );

  @override
  ConsumerState<LoanAdjustmentSheet> createState() =>
      _LoanAdjustmentSheetState();
}

class _LoanAdjustmentSheetState extends ConsumerState<LoanAdjustmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _idempotencyKey = IdGenerator.generate();
  late DateTime _date = DateTime.now();
  String? _accountId;
  bool _saving = false;

  bool get _prepay => widget.kind == LoanAdjustmentKind.principalPrepayment;
  double? get _value => double.tryParse(_amount.text.trim());

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose an account.')));
      return;
    }
    final amount = _value!;
    final prepayment = _prepay
        ? previewPrincipalPrepayment(
            loan: widget.loan,
            installments: widget.installments,
            principalAmount: amount,
            date: _date,
          )
        : null;
    if (prepayment != null &&
        amount > prepayment.maximumPrincipalAmount + 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Amount exceeds the principal remaining after the scheduled payment.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(loanAdvancePaymentRepositoryProvider);
      final outcome = _prepay
          ? (await repository.record(
              loan: widget.loan,
              scheduleInstallments: widget.installments,
              accountId: _accountId!,
              amount: prepayment!.transactionAmount,
              date: _date,
              idempotencyKey: _idempotencyKey,
              note: _note.text.trim(),
            )).reamortization
          : (await repository.recordAdditionalDisbursement(
              loan: widget.loan,
              scheduleInstallments: widget.installments,
              accountId: _accountId!,
              amount: amount,
              date: _date,
              idempotencyKey: _idempotencyKey,
              note: _note.text.trim(),
            )).reamortization;
      if (!mounted) return;
      Navigator.of(context).pop();
      final unsolvable =
          outcome is PrepaymentReamortizationUnsolvable ||
          outcome is DisbursementReamortizationUnsolvable;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unsolvable
                ? 'Money recorded. Review loan terms because the schedule could not be adjusted automatically.'
                : _prepay
                ? 'Principal prepayment recorded.'
                : 'Additional disbursement recorded.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not record this operation safely. Refresh the loan and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    _accountId ??=
        accounts.where((a) => a.isDefault).firstOrNull?.id ??
        accounts.firstOrNull?.id;
    final amount = _value;
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final preview = amount != null && amount > 0
        ? (_prepay
              ? previewPrincipalPrepayment(
                  loan: widget.loan,
                  installments: widget.installments,
                  principalAmount: amount,
                  date: _date,
                )
              : previewAdditionalDisbursement(
                  loan: widget.loan,
                  installments: widget.installments,
                  amount: amount,
                ))
        : null;
    final physicalAmount = preview is PrincipalPrepaymentPreview
        ? preview.transactionAmount
        : amount ?? 0;
    final incoming = _prepay
        ? widget.loan.direction == LoanDirection.given
        : widget.loan.direction == LoanDirection.taken;
    final accountAfter = account == null
        ? null
        : account.currentBalance +
              (incoming ? physicalAmount : -physicalAmount);
    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _prepay ? 'Prepay Principal' : 'Additional Disbursement',
        description: _prepay
            ? 'Settle the current due amount and intentionally reduce principal.'
            : widget.loan.direction == LoanDirection.taken
            ? 'Record additional money received from this lender.'
            : 'Record additional money lent to this borrower.',
        confirmLabel: _saving
            ? 'Recording…'
            : _prepay && preview is PrincipalPrepaymentPreview
            ? 'Pay ${CurrencyFormatter.instance.format(preview.transactionAmount)}'
            : amount != null
            ? 'Add ${CurrencyFormatter.instance.format(amount)}'
            : 'Continue',
        isSaving: _saving,
        confirmEnabled: amount != null && amount > 0 && _accountId != null,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Amount & account'),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _prepay
                    ? 'Extra principal amount'
                    : 'Additional amount',
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                return n == null || n <= 0
                    ? 'Enter an amount greater than zero'
                    : null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: InputDecoration(
                labelText: incoming ? 'Into account' : 'From account',
              ),
              items: accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name}${a.accountNumberLast4 == null ? '' : ' ••${a.accountNumberLast4}'}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: AppSizes.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _saving
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _date = d);
                    },
            ),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLines: 2,
            ),
            if (preview != null) ...[
              const SizedBox(height: AppSizes.lg),
              const SectionLabel('Preview'),
              const SizedBox(height: AppSizes.sm),
              Container(
                padding: const EdgeInsets.all(AppSizes.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    if (preview is PrincipalPrepaymentPreview) ...[
                      _row('Scheduled allocation', preview.scheduledAmount),
                      _row('Principal prepayment', preview.principalAmount),
                      _beforeAfter(
                        'Outstanding principal',
                        preview.principalBefore,
                        preview.principalAfter,
                      ),
                      if (preview.outcome case PrepaymentReamortizationSolved(
                        :final remainingInstallmentCount,
                      ))
                        _textBeforeAfter(
                          'Remaining installments',
                          '${preview.installmentCountBefore}',
                          '$remainingInstallmentCount',
                        ),
                    ],
                    if (preview is AdditionalDisbursementPreview) ...[
                      _beforeAfter(
                        'Principal',
                        preview.principalBefore,
                        preview.principalAfter,
                      ),
                      _textBeforeAfter(
                        'Remaining installments',
                        '${preview.remainingInstallmentCount}',
                        '${preview.remainingInstallmentCount}',
                      ),
                      if (preview.outcome case DisbursementReamortizationSolved(
                        :final installmentAmount,
                      ))
                        _beforeAfter(
                          'Installment amount',
                          preview.currentInstallmentAmount ?? 0,
                          installmentAmount,
                        ),
                    ],
                    if (account != null && accountAfter != null)
                      _beforeAfter(
                        account.name,
                        account.currentBalance,
                        accountAfter,
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

  Widget _row(String label, double value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          CurrencyFormatter.instance.format(value),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
  Widget _beforeAfter(String label, double before, double after) =>
      _textBeforeAfter(
        label,
        CurrencyFormatter.instance.format(before),
        CurrencyFormatter.instance.format(after),
      );
  Widget _textBeforeAfter(String label, String before, String after) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(before),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward_rounded, size: 14),
        ),
        Text(after, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
