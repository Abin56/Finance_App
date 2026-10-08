import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/ledger_entry.dart';
import '../../domain/ledger_entry_type.dart';
import '../../domain/person.dart';
import '../../domain/person_cycle_statement.dart';
import '../../domain/person_payment.dart';
import '../providers/people_providers.dart';
import '../providers/person_payment_providers.dart';
import 'person_settlement_row.dart';
import 'record_payment_sheet.dart';

/// The People Ledger for one person on mobile — the same statement engine,
/// cycles, allocation and payment writes as the web app, presented as compact
/// expandable rows instead of a table:
///  - cycle navigator + reconciliation (previous pending, this cycle,
///    received/paid, current pending, advance);
///  - brought-forward obligations, this cycle's obligations, then payments
///    that stand on their own (against an older obligation, or advance);
///  - Record payment / Apply advance, and per row: record, revert, edit, delete
///    — each only where the record can safely support it.
class PersonSettlementSection extends ConsumerStatefulWidget {
  const PersonSettlementSection({super.key, required this.person});
  final Person person;

  @override
  ConsumerState<PersonSettlementSection> createState() => _PersonSettlementSectionState();
}

class _PersonSettlementSectionState extends ConsumerState<PersonSettlementSection> {
  StatementCycle _cycle = StatementCycle.containing(DateTime.now());

  String _money(double v) => CurrencyFormatter.instance.format(v);
  String get _first => widget.person.name.trim().split(RegExp(r'\s+')).first;

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(personStatementSourcesProvider(widget.person.id));
    if (sources == null) {
      return const Padding(padding: EdgeInsets.all(AppSizes.xl), child: Center(child: CircularProgressIndicator()));
    }
    final payable = {for (final p in ref.watch(payableObligationsProvider(widget.person.id))) p.obligation.key: p};
    final accounts = {for (final a in ref.watch(accountsStreamProvider).value ?? const []) a.id: a.name};
    final transactions = {for (final t in ref.watch(transactionsStreamProvider).value ?? const []) t.id: t};
    final entryById = {for (final e in sources.ledgerEntries) e.id: e};

    final statement = sources.statement(_cycle);
    final history = sources.statement(StatementCycle(DateTime(1970), DateTime(2100)));
    final advances = sources.advances();
    double advanceFor(ObligationSide side) => advances.where((a) => a.side == side).fold(0.0, (t, a) => t + a.remaining);

    final paymentsByKey = <String, List<StatementRow>>{};
    for (final r in history.rows) {
      if (!r.isObligation && r.settlesKey != null) paymentsByKey.putIfAbsent(r.settlesKey!, () => []).add(r);
    }
    final carried = history.rows
        .where((r) => r.isObligation && (r.remainingNow ?? 0) > paymentEpsilon && r.date.isBefore(_cycle.start))
        .toList();
    final inCycle = statement.rows.where((r) => r.isObligation).toList().reversed.toList();
    final shownKeys = {...carried.map((r) => r.key), ...inCycle.map((r) => r.key)};
    final standalone = statement.rows
        .where((r) => !r.isObligation && (r.settlesKey == null || !shownKeys.contains(r.settlesKey)))
        .toList()
        .reversed
        .toList();

    String? accountFor(StatementRow payment) {
      final id = payment.key.startsWith('ledger:') ? entryById[payment.key.substring(7)]?.transactionRef : null;
      final t = id == null ? null : transactions[id];
      return t == null ? null : accounts[t.accountId];
    }

    Widget rowFor(StatementRow r, {bool carriedForward = false}) {
      final entry = r.key.startsWith('ledger:') ? entryById[r.key.substring(7)] : null;
      final open = (r.remainingNow ?? 0) > paymentEpsilon;
      final p = payable[r.key];
      final side = r.signedAmount < 0 ? ObligationSide.iOwe : ObligationSide.theyOwe;
      final canApply = r.isObligation && open && p != null && advanceFor(side) > paymentEpsilon;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.sm),
        child: PersonSettlementRow(
          key: ValueKey(r.key),
          row: r,
          personName: widget.person.name,
          sourceKind: entry?.sourceKind,
          carriedForward: carriedForward,
          carriedFromLabel: carriedForward ? '${StatementCycle.containing(r.date).label} cycle' : null,
          payments: paymentsByKey[r.key] ?? const [],
          accountForPayment: accountFor,
          onRecordPayment: r.isObligation && open && p != null
              ? () => RecordPaymentSheet.show(context, widget.person, preselectKey: r.key)
              : null,
          onRevertPayment: (paymentId) => _revert(paymentId),
          onApplyAdvance: canApply ? () => _applyAdvance(r, side, advanceFor(side)) : null,
          onOpen: r.paymentId != null ? () => _paymentActions(r.paymentId!) : null,
          onDelete: _deletable(entry) ? () => _delete(entry!) : null,
        ),
      );
    }

    final theyAdvance = advanceFor(ObligationSide.theyOwe);
    final myAdvance = advanceFor(ObligationSide.iOwe);
    final openTheirs = payable.values.any((p) => p.obligation.side == ObligationSide.theyOwe);
    final openMine = payable.values.any((p) => p.obligation.side == ObligationSide.iOwe);
    final current = StatementCycle.containing(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          IconButton(
            tooltip: 'Previous cycle',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() => _cycle = _cycle.shift(-1)),
          ),
          Expanded(
            child: Text(_cycle.label, textAlign: TextAlign.center, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Next cycle',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _cycle.sameAs(current) ? null : () => setState(() => _cycle = _cycle.shift(1)),
          ),
        ]),
        PersonCycleReconciliation(statement: statement, personName: widget.person.name),
        const SizedBox(height: AppSizes.md),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => RecordPaymentSheet.show(context, widget.person),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record payment'),
            ),
          ),
          if ((theyAdvance > paymentEpsilon && openTheirs) || (myAdvance > paymentEpsilon && openMine)) ...[
            const SizedBox(width: AppSizes.sm),
            OutlinedButton.icon(
              onPressed: () => _applyAdvanceToOldest(theyAdvance > paymentEpsilon && openTheirs ? ObligationSide.theyOwe : ObligationSide.iOwe),
              icon: const Icon(Icons.savings_outlined),
              label: const Text('Apply advance'),
            ),
          ],
        ]),
        const SizedBox(height: AppSizes.md),
        if (carried.isEmpty && inCycle.isEmpty && standalone.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
            child: Text('Nothing with $_first in this cycle.',
                textAlign: TextAlign.center, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        if (carried.isNotEmpty) ...[
          _SectionLabel('Brought forward · ${_money(carried.fold(0.0, (t, r) => t + (r.remainingNow ?? 0)))} open'),
          for (final r in carried) rowFor(r, carriedForward: true),
        ],
        if (inCycle.isNotEmpty) ...[
          const _SectionLabel('This cycle'),
          for (final r in inCycle) rowFor(r),
        ],
        if (standalone.isNotEmpty) ...[
          const _SectionLabel('Payments & advance'),
          for (final r in standalone) rowFor(r),
        ],
      ],
    );
  }

  /// Only records this app can remove without leaving anything behind: a
  /// manual entry with no linked record and no payment recorded against it.
  bool _deletable(LedgerEntry? e) {
    if (e == null || e.transactionRef != null || e.paymentId != null) return false;
    final all = ref.read(personStatementSourcesProvider(widget.person.id))?.ledgerEntries ?? const [];
    return !all.any((x) => !x.isDeleted && x.parentEntryId == e.id);
  }

  Future<void> _delete(LedgerEntry e) async {
    final ok = await _confirm(
      'Delete this entry?',
      '“${e.note.isEmpty ? e.type.label : e.note}” · ${_money(e.amount)} will be removed and your balance with $_first recalculated.',
      'Delete',
    );
    if (!ok) return;
    await _run(() => ref.read(ledgerRepositoryProvider(widget.person.id)).softDeleteEntry(widget.person, e), 'Entry deleted');
  }

  Future<void> _paymentActions(String paymentId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit payment'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(leading: const Icon(Icons.undo_rounded), title: const Text('Revert payment'), onTap: () => Navigator.pop(c, 'revert')),
        ]),
      ),
    );
    if (!mounted) return;
    if (choice == 'revert') return _revert(paymentId);
    if (choice == 'edit') {
      final entries = (ref.read(personStatementSourcesProvider(widget.person.id))?.ledgerEntries ?? const <LedgerEntry>[])
          .where((e) => !e.isDeleted && e.paymentId == paymentId)
          .toList();
      if (entries.isEmpty) return;
      final cashLeg = entries.first.transactionRef == null ? null : ref.read(transactionsStreamProvider).value?.where((t) => t.id == entries.first.transactionRef).firstOrNull;
      final lines = <String, double>{};
      var advance = 0.0;
      for (final e in entries) {
        if (e.isAdvance) {
          advance += e.amount;
        } else {
          lines[e.obligationRef ?? 'ledger:${e.parentEntryId}'] = e.amount;
        }
      }
      final income = entries.first.incomeTransactionRef;
      if (income != null) {
        _snack('This payment has a separate income part — revert it and record it again to change it.');
        return;
      }
      await RecordPaymentSheet.show(
        context,
        widget.person,
        initial: RecordPaymentInitial(
          paymentId: paymentId,
          direction: entries.first.type == LedgerEntryType.receivedBack ? PaymentDirection.theyPaid : PaymentDirection.iPaid,
          amount: round2(entries.fold(0.0, (t, e) => t + e.amount)),
          accountId: cashLeg?.accountId,
          date: entries.first.date,
          lines: lines,
          advance: advance,
        ),
      );
    }
  }

  Future<void> _revert(String paymentId) async {
    final entries = (ref.read(personStatementSourcesProvider(widget.person.id))?.ledgerEntries ?? const <LedgerEntry>[])
        .where((e) => !e.isDeleted && e.paymentId == paymentId)
        .toList();
    final total = entries.fold(0.0, (t, e) => t + e.amount);
    final hasAdvance = entries.any((e) => e.isAdvance);
    final ok = await _confirm(
      'Revert this payment?',
      '${_money(total)} ${entries.firstOrNull?.type == LedgerEntryType.repaid ? 'paid to' : 'received from'} $_first will be removed: '
          'the account movement is reversed and every obligation it paid becomes unpaid again.'
          '${hasAdvance ? ' Advance from it that was applied to later obligations is un-applied too.' : ''}',
      'Revert payment',
    );
    if (!ok) return;
    await _run(() async {
      final repo = await ref.read(personPaymentRepositoryProvider(widget.person.id).future);
      await repo.revertPayment(widget.person, paymentId);
    }, 'Payment reverted');
  }

  Future<void> _applyAdvance(StatementRow r, ObligationSide side, double available) async {
    final amount = round2((r.remainingNow ?? 0) < available ? r.remainingNow! : available);
    final ok = await _confirm(
      'Apply ${_money(amount)} advance?',
      '${r.title}: ${_money(r.remainingNow ?? 0)} open. Advance available ${_money(available)}. '
          'After this: ${_money(round2((r.remainingNow ?? 0) - amount))} open, ${_money(round2(available - amount))} advance left. No money moves.',
      'Apply advance',
    );
    if (!ok) return;
    await _run(() async {
      final sources = ref.read(personStatementSourcesProvider(widget.person.id))!;
      final repo = await ref.read(personPaymentRepositoryProvider(widget.person.id).future);
      await repo.applyAdvance(widget.person, obligationKey: r.key, uses: drawAdvance(sources.advances(), side, amount), date: DateTime.now());
    }, 'Advance applied');
  }

  Future<void> _applyAdvanceToOldest(ObligationSide side) async {
    final oldest = ref
        .read(payableObligationsProvider(widget.person.id))
        .where((p) => p.obligation.side == side)
        .firstOrNull;
    final sources = ref.read(personStatementSourcesProvider(widget.person.id));
    if (oldest == null || sources == null) return;
    final row = sources.allTime().rows.firstWhere((r) => r.key == oldest.obligation.key);
    final available = sources.advances().where((a) => a.side == side).fold(0.0, (t, a) => t + a.remaining);
    await _applyAdvance(row, side, available);
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
    } catch (e) {
      _snack(e.toString().replaceFirst(RegExp(r'^\w*Exception:?\s*'), ''));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSizes.sm, bottom: AppSizes.xs),
        child: Text(text.toUpperCase(),
            style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.colors.onSurfaceVariant)),
      );
}
