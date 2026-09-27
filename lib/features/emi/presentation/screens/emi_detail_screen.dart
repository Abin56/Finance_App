import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/interest/interest_period.dart';
import '../../../../core/interest/interest_type.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../lending/presentation/widgets/loan_emi_ui.dart';
import '../../domain/emi.dart';
import '../../domain/emi_loan_type.dart';
import '../../domain/emi_status.dart';
import '../providers/emi_providers.dart';
import '../widgets/emi_form_sheet.dart';
import '../widgets/emi_installment_tile.dart';
import '../widgets/emi_payment_history_tile.dart';
import '../widgets/emi_tile.dart';
import '../widgets/record_emi_lump_sum_settlement_sheet.dart';
import '../widgets/record_emi_multi_payment_sheet.dart';
import '../widgets/record_emi_payment_sheet.dart';

String _money(double amount) => CurrencyFormatter.instance.format(amount);

/// One EMI's details — the outstanding balance first (hero), one primary
/// action (Record payment) with the rarer ones under "More", the key facts,
/// what it's linked to, upcoming and all installments, and the payment
/// history. Close / Finish early / default / delete stay in the ⋮ menu.
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

    final installmentsAsync = ref.watch(
      installmentsStreamProvider(emi.scheduleId),
    );
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
                final confirmed = await _confirmEarlyClosure(
                  context,
                  remaining,
                );
                if (confirmed != true) return;
                final installments =
                    ref
                        .read(installmentsStreamProvider(emi.scheduleId))
                        .value ??
                    const [];
                await repository.closeEmiEarly(emi, installments);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _CloseAction.close,
                  child: Text('Close EMI'),
                ),
                if (remaining > 0)
                  const PopupMenuItem(
                    value: _CloseAction.closeEarly,
                    child: Text('Finish EMI (clear amount left)'),
                  ),
                if (status == EmiStatus.defaulted)
                  const PopupMenuItem(
                    value: _CloseAction.clearDefaulted,
                    child: Text('Clear defaulted'),
                  )
                else
                  const PopupMenuItem(
                    value: _CloseAction.markDefaulted,
                    child: Text('Mark as defaulted'),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _CloseAction.delete,
                  child: Text(
                    'Delete EMI',
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: installmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong: $error')),
        data: (installments) {
          final sorted = [...installments]
            ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
          final thisWeek = ref.watch(
            thisWeekInstallmentsProvider(emi.scheduleId),
          );
          final thisMonth = ref.watch(
            thisMonthInstallmentsProvider(emi.scheduleId),
          );
          final nextMonth = ref.watch(
            nextMonthInstallmentsProvider(emi.scheduleId),
          );
          final overdue = ref.watch(
            overdueInstallmentsProvider(emi.scheduleId),
          );

          final nextDueInstallment = sorted
              .where((i) => i.remainingAmount > 0)
              .firstOrNull;
          final emiAmount =
              (nextDueInstallment ?? sorted.lastOrNull)?.amountDue ?? 0.0;
          final installmentsPaid = ref.watch(emiInstallmentsPaidProvider(emi));
          final remainingTenure = ref.watch(emiRemainingTenureProvider(emi));
          final done =
              status == EmiStatus.closed || status == EmiStatus.completed;
          final heroNext = done
              ? null
              : sorted
                    .where((i) => !i.isSkipped && i.remainingAmount > 0)
                    .firstOrNull;
          final bookedOn =
              emi.sanctionDate ?? emi.disbursementDate ?? emi.startDate;
          final unit = _unitLabel(emi);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              AppSizes.sm,
              AppSizes.lg,
              AppSizes.xxl,
            ),
            children: [
              // 1. What's left, and what's next.
              LoanEmiDetailHero(
                kindLabel: LoanEmiCopy.emi,
                label: LoanEmiCopy.outstanding,
                amount: remaining,
                paid: installmentsPaid,
                total: emi.installmentCount,
                badges: emiBadges(context, status),
                nextAmount: heroNext?.remainingAmount,
                nextDate: heroNext?.dueDate,
                nextSequence: heroNext?.sequenceNumber,
              ),
              const SizedBox(height: AppSizes.md),

              // 2. One primary action; the rest one tap away.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: nextDueInstallment == null
                          ? null
                          : () => RecordEmiPaymentSheet.show(
                              context,
                              emi,
                              nextDueInstallment,
                            ),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Record payment'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => _showMoreActions(context, ref, emi),
                    icon: const Icon(Icons.more_horiz_rounded),
                    label: const Text('More'),
                  ),
                ],
              ),

              // 3. Key facts.
              const SizedBox(height: AppSizes.lg),
              const LoanEmiSectionTitle('Details'),
              LoanEmiFactGrid(
                facts: [
                  LoanEmiFact('Original amount', _money(emi.principalAmount)),
                  LoanEmiFact('Installment', _money(emiAmount), strong: true),
                  LoanEmiFact('Paid so far', _money(paid)),
                  LoanEmiFact(
                    'Interest',
                    emi.interest == null
                        ? 'No interest'
                        : '${emi.interest!.ratePercent}% ${emi.interest!.period == InterestPeriod.yearly ? 'p.a.' : 'p.m.'} · ${emi.interest!.type == InterestType.flat ? 'flat' : 'reducing'}',
                  ),
                  LoanEmiFact('Tenure', '${emi.installmentCount} $unit'),
                  LoanEmiFact('Remaining', '$remainingTenure $unit'),
                  LoanEmiFact('Booked on', bookedOn.fullDate),
                  LoanEmiFact('Type', emi.loanType.label),
                ],
              ),

              if (emi.interest != null) ...[
                const SizedBox(height: AppSizes.lg),
                const LoanEmiSectionTitle('Principal & interest'),
                _interestGrid(ref, emi),
              ],

              // 4. What it's linked to.
              if (emi.linkedCreditCardId != null ||
                  emi.lenderName?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppSizes.lg),
                const LoanEmiSectionTitle('Linked'),
                _linkedGroup(context, ref, emi),
              ],

              // 5. Installments — what's coming up, then the full schedule.
              const SizedBox(height: AppSizes.lg),
              LoanEmiSectionTitle(
                'Installments',
                trailing: Text(
                  '$installmentsPaid of ${emi.installmentCount} paid',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: loanEmiSecondaryText(context),
                  ),
                ),
              ),
              if (cycleView.previousCyclePending.isNotEmpty)
                _group(
                  context,
                  ref,
                  emi,
                  'Previous cycle pending',
                  cycleView.previousCyclePending,
                ),
              if (overdue.isNotEmpty)
                _group(context, ref, emi, 'Missed payment', overdue),
              if (thisWeek.isNotEmpty)
                _group(context, ref, emi, 'This week', thisWeek),
              if (thisMonth.isNotEmpty)
                _group(context, ref, emi, 'This month', thisMonth),
              if (nextMonth.isNotEmpty)
                _group(context, ref, emi, 'Next month', nextMonth),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  border: Border.all(color: context.colors.outline),
                ),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(
                    AppSizes.sm,
                    0,
                    AppSizes.sm,
                    AppSizes.sm,
                  ),
                  title: Text(
                    'All installments (${sorted.length})',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Tap one to pay it · long-press to skip',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: loanEmiSecondaryText(context),
                    ),
                  ),
                  children: [
                    for (final installment in sorted)
                      _installmentTile(context, ref, emi, installment),
                  ],
                ),
              ),

              // 6. Payment history.
              const SizedBox(height: AppSizes.lg),
              const LoanEmiSectionTitle('Payment history'),
              Builder(
                builder: (context) {
                  final history = ref.watch(emiPaymentHistoryProvider(emi));
                  if (history.isEmpty) {
                    return const EmptyState(
                      icon: Icons.event_note_outlined,
                      title: 'No payments yet',
                      subtitle: 'Record a payment to see it appear here.',
                    );
                  }
                  final sortedHistory = [...history]
                    ..sort((a, b) => b.date.compareTo(a.date));
                  return Column(
                    children: [
                      for (final entry in sortedHistory)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSizes.sm),
                          child: EmiPaymentHistoryTile(entry: entry),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _interestGrid(WidgetRef ref, Emi emi) {
    final principalOutstanding = ref.watch(
      emiPrincipalOutstandingProvider(emi),
    );
    final interestOutstanding = ref.watch(emiInterestOutstandingProvider(emi));
    final totalInterestPayable = ref.watch(
      emiTotalInterestPayableProvider(emi),
    );
    final interestPaid = (totalInterestPayable - interestOutstanding).clamp(
      0,
      totalInterestPayable,
    );
    return LoanEmiFactGrid(
      facts: [
        LoanEmiFact('Principal left', _money(principalOutstanding)),
        LoanEmiFact('Interest left', _money(interestOutstanding)),
        LoanEmiFact('Total interest', _money(totalInterestPayable)),
        LoanEmiFact('Interest paid', _money(interestPaid.toDouble())),
      ],
    );
  }

  Widget _linkedGroup(BuildContext context, WidgetRef ref, Emi emi) {
    final cardId = emi.linkedCreditCardId;
    final lender = emi.lenderName?.trim();
    final rows = <Widget>[
      if (cardId != null) ...[
        LoanEmiLinkedRow(
          icon: Icons.credit_card_rounded,
          label: 'Credit card',
          value: emiLinkedCardLabel(ref, emi) ?? 'Credit card',
          onOpen: () => context.push('${AppRoutes.creditCards}/$cardId'),
        ),
        Divider(height: 1, color: context.colors.outline),
        _reservedRow(context, ref, cardId),
      ],
      if (lender != null && lender.isNotEmpty) ...[
        if (cardId != null) Divider(height: 1, color: context.colors.outline),
        LoanEmiLinkedRow(
          icon: Icons.storefront_outlined,
          label: 'Lender / store',
          value: lender,
        ),
      ],
    ];
    return LoanEmiGroup(children: rows);
  }

  /// How much of the card's limit this card's linked EMIs still hold.
  Widget _reservedRow(BuildContext context, WidgetRef ref, String cardId) {
    final reserved = ref.watch(linkedEmiPrincipalForCardProvider(cardId));
    final restored = ref.watch(principalRestoredForCardProvider(cardId));
    final secondary = loanEmiSecondaryText(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Card limit still held',
              style: context.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ),
          Text(
            _money((reserved - restored).clamp(0, reserved).toDouble()),
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            ' of ${_money(reserved)}',
            style: context.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoreActions(BuildContext context, WidgetRef ref, Emi emi) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return ListTile(
            minTileHeight: 64,
            leading: LoanEmiIconBox(icon: icon, size: 38),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                icon: Icons.checklist_rounded,
                title: 'Pay Multiple EMIs',
                subtitle:
                    'Make one payment toward multiple unpaid installments.',
                onTap: () {
                  final unpaid =
                      (ref
                                  .read(
                                    installmentsStreamProvider(emi.scheduleId),
                                  )
                                  .value ??
                              const [])
                          .where((i) => i.remainingAmount > 0)
                          .toList();
                  RecordEmiMultiPaymentSheet.show(context, emi, unpaid);
                },
              ),
              option(
                icon: Icons.request_quote_outlined,
                title: 'Settle lump sum',
                subtitle: 'Record one lump-sum payment against this EMI.',
                onTap: () => RecordEmiLumpSumSettlementSheet.show(context, emi),
              ),
              option(
                icon: Icons.update_rounded,
                title: 'Change tenure or terms',
                subtitle: 'Only unpaid installments are recalculated.',
                onTap: () => EmiFormSheet.show(context, emi: emi),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _group(
    BuildContext context,
    WidgetRef ref,
    Emi emi,
    String title,
    List<Installment> installments,
  ) {
    final descending = [...installments]
      ..sort((a, b) => b.sequenceNumber.compareTo(a.sequenceNumber));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.textTheme.labelLarge?.copyWith(
              color: loanEmiSecondaryText(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          for (final installment in descending)
            _installmentTile(context, ref, emi, installment),
        ],
      ),
    );
  }

  Widget _installmentTile(
    BuildContext context,
    WidgetRef ref,
    Emi emi,
    Installment installment,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: GestureDetector(
        onLongPress: () =>
            _showInstallmentActions(context, ref, emi, installment),
        child: EmiInstallmentTile(
          installment: installment,
          onTap: installment.remainingAmount <= 0
              ? null
              : () => RecordEmiPaymentSheet.show(context, emi, installment),
        ),
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
                onTap: () =>
                    Navigator.of(context).pop(_InstallmentAction.unskip),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;

    final installmentRepository = ref.read(
      installmentRepositoryProvider(emi.scheduleId),
    );
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Finish Early'),
          ),
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// "months" for monthly/custom/one-time schedules, "weeks" for weekly.
  String _unitLabel(Emi emi) {
    return emi.installmentFrequency.name == 'weekly' ? 'weeks' : 'months';
  }
}

enum _CloseAction { close, closeEarly, markDefaulted, clearDefaulted, delete }

enum _InstallmentAction { skip, unskip }
