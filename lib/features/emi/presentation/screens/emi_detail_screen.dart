import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/charts/loan_progress_ring.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/emi.dart';
import '../../domain/emi_loan_type.dart';
import '../../domain/emi_status.dart';
import '../providers/emi_providers.dart';
import '../widgets/emi_form_sheet.dart';
import '../widgets/emi_installment_tile.dart';
import '../widgets/emi_payment_history_tile.dart';
import '../widgets/record_emi_multi_payment_sheet.dart';
import '../widgets/record_emi_payment_sheet.dart';

/// One EMI's detail — header stats (principal/paid/remaining, plus
/// interest breakdown when the EMI carries interest), its installments
/// grouped by This week / This month / Next month / Overdue (long-press an
/// installment to skip/unskip it), a full payment history timeline, and
/// Close / Close early (write off the remaining balance) actions.
class EmiDetailScreen extends ConsumerWidget {
  const EmiDetailScreen({super.key, required this.emiId});

  final String emiId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emis = ref.watch(emisStreamProvider).value ?? const [];
    final emi = emis.where((e) => e.id == emiId).firstOrNull;

    if (emi == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final installmentsAsync = ref.watch(installmentsStreamProvider(emi.scheduleId));
    final status = ref.watch(emiStatusProvider(emi));
    final remaining = ref.watch(emiRemainingAmountProvider(emi));
    final paid = ref.watch(emiTotalPaidProvider(emi));
    final repository = ref.watch(emiRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(emi.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Pay multiple payments together',
            onPressed: () {
              final unpaid = (ref.read(installmentsStreamProvider(emi.scheduleId)).value ?? const [])
                  .where((i) => i.remainingAmount > 0)
                  .toList();
              RecordEmiMultiPaymentSheet.show(context, emi, unpaid);
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit EMI',
            onPressed: () => EmiFormSheet.show(context, emi: emi),
          ),
          if (status == EmiStatus.closed)
            IconButton(
              icon: const Icon(Icons.lock_open_rounded),
              tooltip: 'Reopen EMI',
              onPressed: () => repository.reopenEmi(emi),
            )
          else
            PopupMenuButton<_CloseAction>(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) async {
                if (action == _CloseAction.close) {
                  await repository.closeEmi(emi);
                  return;
                }
                if (action == _CloseAction.markDefaulted) {
                  await repository.markDefaulted(emi);
                  return;
                }
                if (action == _CloseAction.clearDefaulted) {
                  await repository.clearDefaulted(emi);
                  return;
                }
                if (!context.mounted) return;
                final confirmed = await _confirmEarlyClosure(context, remaining);
                if (confirmed != true) return;
                final installments = ref.read(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
                await repository.closeEmiEarly(emi, installments);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: _CloseAction.close, child: Text('Close EMI')),
                if (remaining > 0)
                  const PopupMenuItem(
                    value: _CloseAction.closeEarly,
                    child: Text('Finish EMI (clear amount left)'),
                  ),
                if (status == EmiStatus.defaulted)
                  const PopupMenuItem(value: _CloseAction.clearDefaulted, child: Text('Clear defaulted'))
                else
                  const PopupMenuItem(value: _CloseAction.markDefaulted, child: Text('Mark as defaulted')),
              ],
            ),
        ],
      ),
      body: installmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (installments) {
          final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
          final thisWeek = ref.watch(thisWeekInstallmentsProvider(emi.scheduleId));
          final thisMonth = ref.watch(thisMonthInstallmentsProvider(emi.scheduleId));
          final nextMonth = ref.watch(nextMonthInstallmentsProvider(emi.scheduleId));
          final overdue = ref.watch(overdueInstallmentsProvider(emi.scheduleId));

          final totalDue = sorted.fold(0.0, (sum, i) => sum + i.amountDue);
          final completion = totalDue == 0 ? 0.0 : paid / totalDue;
          final nextDue = sorted.where((i) => i.remainingAmount > 0).firstOrNull;
          final expectedClosing = sorted.isEmpty ? null : sorted.last.dueDate;

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSizes.lg),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSizes.xs,
                      runSpacing: AppSizes.xs,
                      children: [
                        Chip(
                          avatar: Icon(emi.loanType.icon, size: AppSizes.iconSm),
                          label: Text(emi.loanType.label),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          avatar: Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                          label: Text(status.label),
                          labelStyle: TextStyle(color: status.color),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.lg),
                    Row(
                      children: [
                        LoanProgressRing(
                          progress: completion,
                          color: status.color,
                          centerLabel: completion.asPercent,
                          centerSubLabel: 'paid',
                        ),
                        const SizedBox(width: AppSizes.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _statRow(context, 'Loan amount', emi.principalAmount),
                              _statRow(context, 'Amount paid', paid),
                              _statRow(context, 'Amount left', remaining),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (emi.interest != null) ...[
                      const Divider(height: AppSizes.xl),
                      _statRow(context, 'Loan amount left', _remainingPrincipal(sorted)),
                      _statRow(context, 'Interest left', _remainingInterest(sorted)),
                    ],
                    const Divider(height: AppSizes.xl),
                    if (nextDue != null) _dateRow(context, 'Next Due', nextDue.dueDate),
                    if (expectedClosing != null) _dateRow(context, 'Expected Closing', expectedClosing),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Container(
                padding: const EdgeInsets.all(AppSizes.lg),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Loan info', style: context.textTheme.titleMedium),
                    const SizedBox(height: AppSizes.sm),
                    if (emi.loanNumber != null) _textRow(context, 'Loan number', emi.loanNumber!),
                    if (emi.lenderName != null && emi.lenderName!.isNotEmpty)
                      _textRow(context, 'Bank name', emi.lenderName!),
                    if (emi.branch != null) _textRow(context, 'Branch', emi.branch!),
                    if (emi.customerId != null) _textRow(context, 'Customer ID', emi.customerId!),
                    if (emi.sanctionDate != null) _dateRow(context, 'Sanction date', emi.sanctionDate!),
                    if (emi.disbursementDate != null) _dateRow(context, 'Loan Taken', emi.disbursementDate!),
                    _dateRow(context, 'First EMI', emi.startDate),
                    _textRow(context, 'Monthly Due', _ordinalDayLabel(emi.dueDayOfMonth ?? emi.startDate.day)),
                    if (emi.isAutoDebitEnabled)
                      _textRow(context, 'Auto debit', emi.autoDebitAccount ?? 'Enabled'),
                    if (emi.linkedCreditCardId != null)
                      _textRow(
                        context,
                        'Linked credit card',
                        ref.watch(accountForCardProvider(emi.linkedCreditCardId!))?.name ?? 'Card',
                      ),
                  ],
                ),
              ),
              if (_hasCharges(emi)) ...[
                const SizedBox(height: AppSizes.lg),
                Container(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Charges', style: context.textTheme.titleMedium),
                      const SizedBox(height: AppSizes.sm),
                      if (emi.processingFee > 0) _statRow(context, 'Processing fee', emi.processingFee),
                      if (emi.insuranceAmount > 0) _statRow(context, 'Insurance', emi.insuranceAmount),
                      if (emi.extraCharges > 0) _statRow(context, 'Other charges', emi.extraCharges),
                      if (emi.foreclosureAmount != null)
                        _statRow(context, 'Foreclosure amount', emi.foreclosureAmount!),
                      if (emi.prepaymentCharges != null)
                        _statRow(context, 'Prepayment charges', emi.prepaymentCharges!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.lg),
              if (overdue.isNotEmpty) _group(context, ref, emi, 'Missed Payment', overdue),
              if (thisWeek.isNotEmpty) _group(context, ref, emi, 'This week', thisWeek),
              if (thisMonth.isNotEmpty) _group(context, ref, emi, 'This month', thisMonth),
              if (nextMonth.isNotEmpty) _group(context, ref, emi, 'Next month', nextMonth),
              Text('Payment Records', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              Builder(builder: (context) {
                final history = ref.watch(emiPaymentHistoryProvider(emi));
                if (history.isEmpty) {
                  return const EmptyState(
                    icon: Icons.event_note_outlined,
                    title: 'No payments',
                    subtitle: 'Record a payment to see it appear here.',
                  );
                }
                final sortedHistory = [...history]..sort((a, b) => b.date.compareTo(a.date));
                return Column(
                  children: [
                    for (final entry in sortedHistory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.sm),
                        child: EmiPaymentHistoryTile(entry: entry),
                      ),
                  ],
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _group(BuildContext context, WidgetRef ref, Emi emi, String title, List<Installment> installments) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          for (final installment in installments)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: GestureDetector(
                onLongPress: () => _showInstallmentActions(context, ref, emi, installment),
                child: EmiInstallmentTile(
                  installment: installment,
                  onTap: installment.remainingAmount <= 0
                      ? null
                      : () => RecordEmiPaymentSheet.show(context, emi, installment),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showInstallmentActions(
    BuildContext context,
    WidgetRef ref,
    Emi emi,
    Installment installment,
  ) async {
    final action = await showModalBottomSheet<_InstallmentAction>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!installment.isSkipped)
              ListTile(
                leading: const Icon(Icons.skip_next_rounded),
                title: const Text('Skip This Month'),
                onTap: () => Navigator.of(context).pop(_InstallmentAction.skip),
              )
            else
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('Undo Skip'),
                onTap: () => Navigator.of(context).pop(_InstallmentAction.unskip),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;

    final installmentRepository = ref.read(installmentRepositoryProvider(emi.scheduleId));
    if (action == _InstallmentAction.skip) {
      await installmentRepository.skipInstallment(installment);
    } else {
      await installmentRepository.unskipInstallment(installment);
    }
  }

  Future<bool?> _confirmEarlyClosure(BuildContext context, double remaining) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finish EMI early?'),
        content: Text(
          'This will clear the ${CurrencyFormatter.instance.format(remaining)} amount left and close the EMI. '
          'Unpaid monthly payments will no longer show as to pay.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Finish Early')),
        ],
      ),
    );
  }

  /// Remaining principal across all installments, assuming each
  /// installment's own payments settle its interest portion before its
  /// principal portion (the standard repayment convention) — display-only,
  /// mirrors `LoanDetailScreen`'s equivalent computation.
  double _remainingPrincipal(List<Installment> installments) {
    return installments.fold(0.0, (sum, i) {
      final interestPortion = i.interestPortion ?? 0;
      final principalPortion = i.principalPortion ?? i.amountDue;
      final paidTowardPrincipal = (i.amountPaid - interestPortion).clamp(0, principalPortion);
      return sum + (principalPortion - paidTowardPrincipal);
    });
  }

  double _remainingInterest(List<Installment> installments) {
    return installments.fold(0.0, (sum, i) {
      final interestPortion = i.interestPortion ?? 0;
      final paidTowardInterest = i.amountPaid.clamp(0, interestPortion);
      return sum + (interestPortion - paidTowardInterest);
    });
  }

  Widget _statRow(BuildContext context, String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          Text(
            CurrencyFormatter.instance.format(value),
            style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _dateRow(BuildContext context, String label, DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          Text(date.fullDate, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _textRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          Flexible(
            child: Text(
              value,
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  /// "Every 5th" / "Every 21st" — a plain-language label for a day of
  /// month, used for [Emi.dueDayOfMonth] (or its `startDate.day` fallback).
  String _ordinalDayLabel(int day) {
    final suffix = switch (day) {
      1 || 21 || 31 => 'st',
      2 || 22 => 'nd',
      3 || 23 => 'rd',
      _ => 'th',
    };
    return 'Every $day$suffix';
  }

  bool _hasCharges(Emi emi) {
    return emi.processingFee > 0 ||
        emi.insuranceAmount > 0 ||
        emi.extraCharges > 0 ||
        emi.foreclosureAmount != null ||
        emi.prepaymentCharges != null;
  }
}

enum _CloseAction { close, closeEarly, markDefaulted, clearDefaulted }

enum _InstallmentAction { skip, unskip }
