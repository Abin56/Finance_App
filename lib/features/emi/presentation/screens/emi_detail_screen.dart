import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../domain/emi.dart';
import '../../domain/emi_loan_type.dart';
import '../../domain/emi_status.dart';
import '../providers/emi_providers.dart';
import '../widgets/emi_form_sheet.dart';
import '../widgets/emi_installment_tile.dart';
import '../widgets/emi_payment_history_tile.dart';
import '../widgets/record_emi_lump_sum_settlement_sheet.dart';
import '../widgets/record_emi_multi_payment_sheet.dart';
import '../widgets/record_emi_payment_sheet.dart';

/// One EMI's detail — a premium, banking-app-style summary: hero progress
/// card, loan overview, outstanding principal/interest split (interest-
/// bearing EMIs only), overall progress, linked-credit-card standing (card-
/// linked EMIs only), an installment timeline, a lifetime statistics card,
/// quick actions, and the full payment history. Close / Close early (write
/// off the remaining balance) / default actions live in the app bar.
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
    final cycleView = ref.watch(emiCycleViewRecordProvider(emi));

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
            icon: const Icon(Icons.request_quote_outlined),
            tooltip: 'Settle lump sum',
            onPressed: () => RecordEmiLumpSumSettlementSheet.show(context, emi),
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
                if (action == _CloseAction.delete) {
                  if (!context.mounted) return;
                  final confirmed = await _confirmDelete(context, emi.name);
                  if (confirmed != true) return;
                  await repository.permanentlyDeleteEmi(emi);
                  if (context.mounted) Navigator.of(context).pop();
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
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: _CloseAction.delete,
                  child: Text('Delete EMI', style: TextStyle(color: Colors.red)),
                ),
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

          final nextDueInstallment = sorted.where((i) => i.remainingAmount > 0).firstOrNull;
          final emiAmount = (nextDueInstallment ?? sorted.lastOrNull)?.amountDue ?? 0.0;
          final installmentsPaid = ref.watch(emiInstallmentsPaidProvider(emi));
          final remainingTenure = ref.watch(emiRemainingTenureProvider(emi));
          final progress = ref.watch(emiLoanProgressProvider(emi));

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              _heroCard(context, emi, status, emiAmount, installmentsPaid, progress, nextDueInstallment),
              const SizedBox(height: AppSizes.lg),
              _loanOverviewCard(context, emi, emiAmount, remainingTenure),
              if (emi.interest != null) ...[
                const SizedBox(height: AppSizes.lg),
                _outstandingCard(context, ref, emi),
              ],
              const SizedBox(height: AppSizes.lg),
              _progressCard(context, paid, remaining, progress),
              if (emi.linkedCreditCardId != null) ...[
                const SizedBox(height: AppSizes.lg),
                _creditCardLinkCard(context, ref, emi),
              ],
              const SizedBox(height: AppSizes.lg),
              _timelineSection(context, ref, emi, cycleView, overdue, thisWeek, thisMonth, nextMonth),
              if (emi.interest != null) ...[
                const SizedBox(height: AppSizes.lg),
                _statisticsCard(context, ref, emi),
              ],
              const SizedBox(height: AppSizes.lg),
              _quickActions(context, ref, emi, status, nextDueInstallment),
              const SizedBox(height: AppSizes.lg),
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

  Widget _card(BuildContext context, {required List<Widget> children, bool elevated = false}) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: elevated ? AppShadows.elevated(context) : AppShadows.soft(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _heroCard(
    BuildContext context,
    Emi emi,
    EmiStatus status,
    double emiAmount,
    int installmentsPaid,
    double progress,
    Installment? nextDue,
  ) {
    return _card(
      context,
      elevated: true,
      children: [
        Row(
          children: [
            Icon(emi.loanType.icon, size: AppSizes.iconMd, color: context.colors.primary),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(emi.loanType.label, style: context.textTheme.titleMedium),
            ),
            Chip(
              avatar: Icon(status.icon, size: AppSizes.iconSm, color: status.color),
              label: Text(status.label),
              labelStyle: TextStyle(color: status.color),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        Text(
          '${CurrencyFormatter.instance.format(emiAmount)} / month',
          style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSizes.md),
        ProgressBar(progress: progress, label: '$installmentsPaid / ${emi.installmentCount} EMIs Paid'),
        if (nextDue != null) ...[
          const SizedBox(height: AppSizes.md),
          _statRow(context, 'Next EMI', nextDue.dueDate.fullDate, isDate: true),
        ],
      ],
    );
  }

  Widget _loanOverviewCard(BuildContext context, Emi emi, double emiAmount, int remainingTenure) {
    final bookedOn = emi.sanctionDate ?? emi.disbursementDate ?? emi.startDate;
    return _card(
      context,
      children: [
        Text('Loan Overview', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        _statRow(context, 'Loan Amount', CurrencyFormatter.instance.format(emi.principalAmount)),
        _statRow(context, 'Booked On', bookedOn.fullDate, isDate: true),
        if (emi.interest != null)
          _statRow(context, 'Interest', '${emi.interest!.ratePercent}% ${emi.interest!.period.label}'),
        _statRow(context, 'Tenure', '${emi.installmentCount} ${_unitLabel(emi)}'),
        _statRow(context, 'EMI', CurrencyFormatter.instance.format(emiAmount)),
        _statRow(context, 'Remaining', '$remainingTenure ${_unitLabel(emi)}'),
      ],
    );
  }

  Widget _outstandingCard(BuildContext context, WidgetRef ref, Emi emi) {
    final principalOutstanding = ref.watch(emiPrincipalOutstandingProvider(emi));
    final interestOutstanding = ref.watch(emiInterestOutstandingProvider(emi));
    return _card(
      context,
      children: [
        Text('Outstanding', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        _statRow(context, 'Outstanding Principal', CurrencyFormatter.instance.format(principalOutstanding)),
        _statRow(context, 'Outstanding Interest', CurrencyFormatter.instance.format(interestOutstanding)),
        const Divider(height: AppSizes.lg),
        _statRow(
          context,
          'Total Outstanding',
          CurrencyFormatter.instance.format(principalOutstanding + interestOutstanding),
          emphasize: true,
        ),
      ],
    );
  }

  Widget _progressCard(BuildContext context, double paid, double remaining, double progress) {
    return _card(
      context,
      children: [
        Text('Progress', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        _statRow(context, 'Paid', CurrencyFormatter.instance.format(paid)),
        _statRow(context, 'Remaining', CurrencyFormatter.instance.format(remaining)),
        const SizedBox(height: AppSizes.sm),
        ProgressBar(progress: progress, label: 'Progress · ${progress.asPercent}'),
      ],
    );
  }

  Widget _creditCardLinkCard(BuildContext context, WidgetRef ref, Emi emi) {
    final cardId = emi.linkedCreditCardId!;
    final cardName = ref.watch(accountForCardProvider(cardId))?.name ?? 'Card';
    final reserved = ref.watch(linkedEmiPrincipalForCardProvider(cardId));
    final restored = ref.watch(principalRestoredForCardProvider(cardId));
    return _card(
      context,
      children: [
        Text('Linked Credit Card', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        _statRow(context, 'Card', cardName),
        _statRow(context, 'Reserved Credit', CurrencyFormatter.instance.format(reserved)),
        _statRow(context, 'Credit Restored', CurrencyFormatter.instance.format(restored)),
        _statRow(
          context,
          'Remaining Reserved',
          CurrencyFormatter.instance.format((reserved - restored).clamp(0, reserved)),
          emphasize: true,
        ),
      ],
    );
  }

  Widget _timelineSection(
    BuildContext context,
    WidgetRef ref,
    Emi emi,
    EmiCycleView cycleView,
    List<Installment> overdue,
    List<Installment> thisWeek,
    List<Installment> thisMonth,
    List<Installment> nextMonth,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Installment Timeline', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        if (cycleView.previousCyclePending.isNotEmpty)
          _group(context, ref, emi, 'Previous Cycle Pending', cycleView.previousCyclePending),
        if (overdue.isNotEmpty) _group(context, ref, emi, 'Missed Payment', overdue),
        if (thisWeek.isNotEmpty) _group(context, ref, emi, 'This week', thisWeek),
        if (thisMonth.isNotEmpty) _group(context, ref, emi, 'This month', thisMonth),
        if (nextMonth.isNotEmpty) _group(context, ref, emi, 'Next month', nextMonth),
      ],
    );
  }

  Widget _statisticsCard(BuildContext context, WidgetRef ref, Emi emi) {
    final totalInterestPayable = ref.watch(emiTotalInterestPayableProvider(emi));
    final interestOutstanding = ref.watch(emiInterestOutstandingProvider(emi));
    final interestPaid = (totalInterestPayable - interestOutstanding).clamp(0, totalInterestPayable);
    return _card(
      context,
      children: [
        Text('Statistics', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSizes.sm),
        _statRow(context, 'Total Interest', CurrencyFormatter.instance.format(totalInterestPayable)),
        _statRow(context, 'Interest Paid', CurrencyFormatter.instance.format(interestPaid)),
        _statRow(context, 'Interest Remaining', CurrencyFormatter.instance.format(interestOutstanding)),
      ],
    );
  }

  Widget _quickActions(
    BuildContext context,
    WidgetRef ref,
    Emi emi,
    EmiStatus status,
    Installment? nextDue,
  ) {
    return Wrap(
      spacing: AppSizes.sm,
      runSpacing: AppSizes.sm,
      children: [
        OutlinedButton.icon(
          onPressed: () => EmiFormSheet.show(context, emi: emi),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Loan'),
        ),
        if (nextDue != null)
          OutlinedButton.icon(
            onPressed: () => RecordEmiPaymentSheet.show(context, emi, nextDue),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record Payment'),
          ),
        OutlinedButton.icon(
          onPressed: () => EmiFormSheet.show(context, emi: emi),
          icon: const Icon(Icons.update_rounded),
          label: const Text('Extend Tenure'),
        ),
        if (status != EmiStatus.closed)
          OutlinedButton.icon(
            onPressed: () => ref.read(emiRepositoryProvider).closeEmi(emi),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('Close Loan'),
          ),
      ],
    );
  }

  Widget _group(BuildContext context, WidgetRef ref, Emi emi, String title, List<Installment> installments) {
    final descending = [...installments]..sort((a, b) => b.sequenceNumber.compareTo(a.sequenceNumber));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.sm),
          for (final installment in descending)
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

  Future<bool?> _confirmDelete(BuildContext context, String emiName) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this EMI?'),
        content: Text(
          '"$emiName" and its entire payment history will be permanently deleted — this cannot be undone. '
          'Use this if the loan was added by mistake. Any credit reserved against a linked card is released.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value, {bool isDate = false, bool emphasize = false}) {
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
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  /// "Months" for monthly/custom/one-time schedules, "Weeks" for weekly —
  /// used for Tenure/Remaining labels on the Loan Overview card.
  String _unitLabel(Emi emi) {
    return emi.installmentFrequency.name == 'weekly' ? 'Weeks' : 'Months';
  }
}

enum _CloseAction { close, closeEarly, markDefaulted, clearDefaulted, delete }

enum _InstallmentAction { skip, unskip }
