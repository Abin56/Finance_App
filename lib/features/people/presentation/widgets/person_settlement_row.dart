import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/person_cycle_statement.dart';

// People settlement presentation for Flutter — the same wording and colour
// system as the web settlement table (flowfi-web
// features/people/lib/settlement-presentation.ts). Presentation only: every
// amount is a [StatementRow] / [PersonCycleStatement] engine value; nothing
// here decides a balance, a settlement or an allocation.

/// What a row IS — its real source, never a generic "transaction".
enum SettlementKind {
  emi,
  loanEmi,
  loanInstallment,
  moneyGiven,
  moneyReceived,
  assigned,
  split,
  paymentReceived,
  paymentMade,
  opening,
  adjustment,
  advance,
  advanceApplied,
}

extension SettlementKindX on SettlementKind {
  String get label => switch (this) {
        SettlementKind.emi => 'EMI',
        SettlementKind.loanEmi => 'Loan EMI',
        SettlementKind.loanInstallment => 'Loan installment',
        SettlementKind.moneyGiven => 'Money given',
        SettlementKind.moneyReceived => 'Money received',
        SettlementKind.assigned => 'Assigned expense',
        SettlementKind.split => 'Split expense',
        SettlementKind.paymentReceived => 'Payment received',
        SettlementKind.paymentMade => 'Payment made',
        SettlementKind.opening => 'Opening balance',
        SettlementKind.adjustment => 'Adjustment',
        SettlementKind.advance => 'Advance',
        SettlementKind.advanceApplied => 'Advance applied',
      };

  IconData get icon => switch (this) {
        SettlementKind.emi || SettlementKind.loanEmi => Icons.event_repeat_rounded,
        SettlementKind.loanInstallment => Icons.account_balance_outlined,
        SettlementKind.moneyGiven => Icons.north_east_rounded,
        SettlementKind.moneyReceived => Icons.south_west_rounded,
        SettlementKind.assigned => Icons.assignment_ind_outlined,
        SettlementKind.split => Icons.call_split_rounded,
        SettlementKind.paymentReceived || SettlementKind.paymentMade => Icons.payments_outlined,
        SettlementKind.opening || SettlementKind.adjustment => Icons.balance_rounded,
        SettlementKind.advance || SettlementKind.advanceApplied => Icons.savings_outlined,
      };

  bool get isPayment =>
      this == SettlementKind.paymentReceived ||
      this == SettlementKind.paymentMade ||
      this == SettlementKind.advance ||
      this == SettlementKind.advanceApplied;
}

/// Functional colours, saturated enough for low-contrast displays.
abstract class SettlementColors {
  static const receivable = AppColors.income;
  static const payable = AppColors.expense;
  static const emi = Color(0xFFD98200);
  static const loan = Color(0xFF5B5BD6);
  static const split = AppColors.info;
  static const assigned = Color(0xFFB0409A);
  static const advance = Color(0xFF0F9C94);
  static const carried = Color(0xFF55606E);
  static const partial = AppColors.warning;
  static const overdue = AppColors.error;
}

String _firstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
}

String _money(double v) => CurrencyFormatter.instance.format(v);

/// The row's kind. [sourceKind] is the backing ledger entry's `sourceKind`
/// (e.g. `assignedExpense`), when the caller has it.
SettlementKind settlementKindOf(StatementRow row, {String? sourceKind}) {
  switch (row.category) {
    case StatementCategory.emi:
      return row.key.startsWith('loan-inst:') ? SettlementKind.loanEmi : SettlementKind.emi;
    case StatementCategory.loan:
      return SettlementKind.loanInstallment;
    case StatementCategory.split:
      return sourceKind == 'assignedExpense' ? SettlementKind.assigned : SettlementKind.split;
    case StatementCategory.gave:
      if (sourceKind == 'assignedExpense') return SettlementKind.assigned;
      if (sourceKind == 'splitExpense') return SettlementKind.split;
      return SettlementKind.moneyGiven;
    case StatementCategory.borrowed:
      return SettlementKind.moneyReceived;
    case StatementCategory.received:
      return SettlementKind.paymentReceived;
    case StatementCategory.repaid:
      return SettlementKind.paymentMade;
    case StatementCategory.opening:
      return SettlementKind.opening;
    case StatementCategory.adjustment:
      return SettlementKind.adjustment;
    case StatementCategory.advance:
      return SettlementKind.advance;
    case StatementCategory.advanceApplied:
      return SettlementKind.advanceApplied;
  }
}

/// Owed to me (+) or by me (−), from the engine's signed effect.
bool _theyOwe(StatementRow row) => row.signedAmount >= 0;

Color settlementColorOf(StatementRow row, SettlementKind kind) => switch (kind) {
      SettlementKind.emi || SettlementKind.loanEmi => SettlementColors.emi,
      SettlementKind.loanInstallment => SettlementColors.loan,
      SettlementKind.split => SettlementColors.split,
      SettlementKind.assigned => SettlementColors.assigned,
      SettlementKind.paymentReceived => SettlementColors.receivable,
      SettlementKind.paymentMade => SettlementColors.carried,
      SettlementKind.advance || SettlementKind.advanceApplied => SettlementColors.advance,
      _ => _theyOwe(row) ? SettlementColors.receivable : SettlementColors.payable,
    };

/// Paid so far on an obligation (amount − remainingNow); null when the row
/// carries no settlement state.
double? settlementPaidOf(StatementRow row) {
  final remaining = row.remainingNow;
  if (!row.isObligation || remaining == null) return null;
  return ((row.amount - remaining) * 100).roundToDouble() / 100;
}

int _day(DateTime d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

typedef SettlementStatus = ({String label, String? detail, Color color});

/// The PERSON's status in human words, from the engine's remaining amount and
/// the due date — never the lender's EMI status.
SettlementStatus settlementStatusOf(StatementRow row, SettlementKind kind, String personName, {DateTime? now}) {
  final name = _firstName(personName);
  final today = now ?? DateTime.now();
  switch (kind) {
    case SettlementKind.paymentReceived:
      return (label: 'Received', detail: 'From $name', color: SettlementColors.receivable);
    case SettlementKind.paymentMade:
      return (label: 'Paid', detail: 'To $name', color: SettlementColors.carried);
    case SettlementKind.advance:
      return (label: 'Advance available', detail: 'Not yet applied', color: SettlementColors.advance);
    case SettlementKind.advanceApplied:
      return (label: 'Advance used', detail: 'No new money moved', color: SettlementColors.advance);
    default:
      break;
  }
  final remaining = row.remainingNow;
  final theyOwe = _theyOwe(row);
  if (remaining == null) {
    return theyOwe
        ? (label: '$name owes', detail: "Part of $name's balance", color: SettlementColors.receivable)
        : (label: 'You owe', detail: 'Part of your balance with $name', color: SettlementColors.payable);
  }
  final left = _money(remaining);
  if (remaining < 0.005) {
    return (label: 'Paid in full', detail: theyOwe ? '$name paid ${_money(row.amount)}' : 'You paid ${_money(row.amount)}', color: SettlementColors.receivable);
  }
  final overdue = kind == SettlementKind.loanInstallment && _day(row.date) < _day(today);
  if (overdue) {
    return (label: 'Overdue', detail: theyOwe ? '$name still owes you $left' : 'You still owe $name $left', color: SettlementColors.overdue);
  }
  if (remaining < row.amount - 0.005) {
    return (label: 'Partially paid', detail: theyOwe ? '$name still owes $left' : 'You still owe $left', color: SettlementColors.partial);
  }
  final isInstallment = kind == SettlementKind.emi || kind == SettlementKind.loanEmi || kind == SettlementKind.loanInstallment;
  if (isInstallment && _day(row.date) > _day(today)) {
    return (
      label: kind == SettlementKind.loanInstallment ? 'Upcoming installment' : 'Upcoming EMI',
      detail: 'Due ${StatementCycle.formatDate(row.date)}',
      color: SettlementColors.carried,
    );
  }
  return theyOwe
      ? (label: 'Payment due', detail: '$name owes you $left', color: SettlementColors.receivable)
      : (label: 'You need to pay', detail: 'You owe $name $left', color: SettlementColors.payable);
}

/// Person-aware title: a user's note is kept; generic engine titles become
/// "Money given to Amma" etc.
String settlementTitleOf(StatementRow row, SettlementKind kind, String personName) {
  const generic = {'Money I Gave', 'Money I Borrowed', 'Payment received', 'Payment made', 'Adjustment'};
  if (!generic.contains(row.title)) return row.title;
  final name = _firstName(personName);
  return switch (kind) {
    SettlementKind.moneyGiven => 'Money given to $name',
    SettlementKind.moneyReceived => 'Money received from $name',
    SettlementKind.paymentReceived => 'Payment from $name',
    SettlementKind.paymentMade => 'Payment to $name',
    SettlementKind.adjustment => 'Balance correction',
    _ => row.title,
  };
}

/// One sentence stating who owes whom — never a bare +/− sign.
String settlementRelationOf(StatementRow row, SettlementKind kind, String personName) {
  final name = _firstName(personName);
  final amount = _money(row.amount);
  final theyOwe = _theyOwe(row);
  final installment = row.installmentNumber == null ? 'Installment' : 'Installment #${row.installmentNumber}';
  return switch (kind) {
    SettlementKind.moneyGiven => 'You gave $name $amount',
    SettlementKind.moneyReceived => '$name gave you $amount',
    SettlementKind.assigned => theyOwe ? 'Assigned to $name · $name pays $amount' : 'Assigned to you · you pay $amount',
    SettlementKind.split => theyOwe ? "$name's share of a split expense" : 'Your share of a split with $name',
    SettlementKind.emi || SettlementKind.loanEmi => '$installment · $name repays you',
    SettlementKind.loanInstallment => '$installment · ${theyOwe ? '$name repays you' : 'you repay $name'}',
    SettlementKind.paymentReceived =>
      row.settles != null ? 'You received $amount from $name · for ${row.settles!.title}' : 'You received $amount from $name',
    SettlementKind.paymentMade => row.settles != null ? 'You paid $name $amount · for ${row.settles!.title}' : 'You paid $name $amount',
    SettlementKind.opening => theyOwe ? '$name owed you $amount when tracking began' : 'You owed $name $amount when tracking began',
    SettlementKind.adjustment => theyOwe ? 'Correction · $name owes you $amount more' : 'Correction · you owe $name $amount more',
    SettlementKind.advance =>
      row.advanceDelta > 0 ? 'You paid $name $amount ahead · held as advance' : '$name paid you $amount ahead · held as advance',
    SettlementKind.advanceApplied => row.settles != null ? '$amount of advance used for ${row.settles!.title}' : '$amount of advance used',
  };
}

// ---------------------------------------------------------------------------
// Row widget
// ---------------------------------------------------------------------------

/// A compact financial row for the People statement — phones never get a
/// squeezed desktop table. Title, semantic type badge, date, original / paid /
/// remaining and a human status; tap expands it in place with the payment
/// history and only the actions this row supports. Actions are callbacks the
/// screen wires to its existing flows.
class PersonSettlementRow extends StatefulWidget {
  const PersonSettlementRow({
    super.key,
    required this.row,
    required this.personName,
    this.sourceKind,
    this.carriedForward = false,
    this.carriedFromLabel,
    this.payments = const [],
    this.accountForPayment,
    this.now,
    this.onRecordPayment,
    this.onRevertPayment,
    this.onApplyAdvance,
    this.onOpen,
    this.onDelete,
  });

  final StatementRow row;
  final String personName;

  /// The backing ledger entry's `sourceKind` (assigned vs split), if known.
  final String? sourceKind;

  /// An open obligation from an earlier cycle, shown as brought forward.
  final bool carriedForward;

  /// e.g. "18 Aug – 17 Sep cycle".
  final String? carriedFromLabel;

  /// Settlement rows whose `settlesKey` is this row's key, oldest first.
  final List<StatementRow> payments;

  /// Account a payment's cash leg moved through ("SBI Savings"), if known.
  final String? Function(StatementRow payment)? accountForPayment;
  final DateTime? now;

  final VoidCallback? onRecordPayment;
  final void Function(String paymentId)? onRevertPayment;
  final VoidCallback? onApplyAdvance;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  @override
  State<PersonSettlementRow> createState() => _PersonSettlementRowState();
}

class _PersonSettlementRowState extends State<PersonSettlementRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final kind = settlementKindOf(row, sourceKind: widget.sourceKind);
    final typeColor = settlementColorOf(row, kind);
    final family = widget.carriedForward ? SettlementColors.carried : typeColor;
    final status = settlementStatusOf(row, kind, widget.personName, now: widget.now);
    final dark = context.isDarkMode;
    final strong = context.colors.onSurface;
    final soft = strong.withValues(alpha: 0.72);
    final paid = settlementPaidOf(row);
    final remaining = row.remainingNow;
    final settled = remaining != null && remaining < 0.005;
    final remainingColor = settled
        ? SettlementColors.receivable
        : status.color == SettlementColors.overdue
            ? SettlementColors.overdue
            : _theyOwe(row)
                ? SettlementColors.receivable
                : SettlementColors.payable;

    return Material(
      color: family.withValues(alpha: dark ? 0.16 : 0.09),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: family, width: 4),
              top: BorderSide(color: strong.withValues(alpha: 0.18)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settlementTitleOf(row, kind, widget.personName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: strong),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Badge(icon: kind.icon, label: kind.label, color: typeColor),
                            if (widget.carriedForward)
                              const _Badge(icon: Icons.history_rounded, label: 'Brought forward', color: SettlementColors.carried),
                            Text(
                              StatementCycle.formatDate(row.date, withYear: true),
                              style: context.textTheme.labelSmall?.copyWith(color: soft, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(remaining ?? row.amount),
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: remaining == null ? strong : remainingColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        remaining == null ? 'AMOUNT' : 'REMAINING',
                        style: context.textTheme.labelSmall?.copyWith(color: soft, fontSize: 9.5, letterSpacing: 0.6, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (widget.carriedForward && widget.carriedFromLabel != null) 'From ${widget.carriedFromLabel}',
                  settlementRelationOf(row, kind, widget.personName),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(color: soft, fontWeight: FontWeight.w500),
              ),
              if (paid != null && remaining != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Figure(label: 'Original', value: _money(row.amount)),
                    _Figure(label: 'Paid', value: _money(paid), color: paid > 0 ? SettlementColors.receivable : null),
                    _Figure(label: 'Remaining', value: _money(remaining)),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  _StatusPill(label: status.label, color: status.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.detail ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelSmall?.copyWith(color: soft, fontWeight: FontWeight.w600),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, size: 20, color: soft),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _open ? _Details(widget: widget, kind: kind, status: status) : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.widget, required this.kind, required this.status});

  final PersonSettlementRow widget;
  final SettlementKind kind;
  final SettlementStatus status;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final name = _firstName(widget.personName);
    final strong = context.colors.onSurface;
    final soft = strong.withValues(alpha: 0.72);
    final paid = settlementPaidOf(row);
    final remaining = row.remainingNow;
    final theyOwe = _theyOwe(row);

    Widget line(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.bodySmall?.copyWith(color: bold ? strong : soft, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              Text(
                value,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? strong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(text, style: context.textTheme.labelSmall?.copyWith(color: soft, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        );

    final pct = paid != null && row.amount > 0 ? (paid / row.amount).clamp(0.0, 1.0) : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: strong.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kind == SettlementKind.emi || kind == SettlementKind.loanEmi || kind == SettlementKind.loanInstallment) ...[
            line(kind == SettlementKind.loanInstallment ? 'Loan' : 'EMI', row.title),
            if (row.installmentNumber != null) line('Installment', '#${row.installmentNumber}'),
            line('Due', StatementCycle.formatDate(row.date, withYear: true)),
          ],
          if (paid != null && remaining != null) ...[
            line(theyOwe ? "$name's responsibility" : 'Your responsibility', _money(row.amount)),
            line(theyOwe ? '$name paid' : 'You paid', _money(paid), color: paid > 0 ? SettlementColors.receivable : null),
            Divider(height: 8, color: strong.withValues(alpha: 0.2)),
            line('Remaining', remaining < 0.005 ? 'Settled' : _money(remaining), bold: true),
            if (pct != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 7,
                        backgroundColor: strong.withValues(alpha: 0.15),
                        color: pct >= 1 ? SettlementColors.receivable : status.color == SettlementColors.overdue ? SettlementColors.overdue : SettlementColors.partial,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(pct * 100).round()}%', style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ] else if (row.settles != null) ...[
            line('Amount', _money(row.amount), bold: true),
            line('Applied to ${row.settles!.title}', _money(row.amount), color: SettlementColors.receivable),
            line('Left on it after this', row.settles!.remainingAfter > 0 ? _money(row.settles!.remainingAfter) : 'Cleared'),
          ] else
            line('Amount', _money(row.amount), bold: true),
          if (widget.payments.isNotEmpty) ...[
            heading('PAYMENT HISTORY'),
            for (final p in widget.payments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          StatementCycle.formatDate(p.date, withYear: true),
                          p.category == StatementCategory.advanceApplied
                              ? 'Advance used'
                              : p.category == StatementCategory.repaid
                                  ? 'Paid to $name'
                                  : 'Received from $name',
                          if (widget.accountForPayment?.call(p) case final account?) '→ $account',
                        ].join('  '),
                        style: context.textTheme.bodySmall?.copyWith(color: soft),
                      ),
                    ),
                    Text(_money(p.amount), style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                    if (p.paymentId != null && widget.onRevertPayment != null)
                      IconButton(
                        tooltip: 'Revert this payment',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.undo_rounded, size: 16),
                        onPressed: () => widget.onRevertPayment!(p.paymentId!),
                      ),
                  ],
                ),
              ),
          ],
          heading('SOURCE'),
          Text(
            '${kind.label} · ${StatementCycle.formatDate(row.date, withYear: true)}${widget.carriedFromLabel != null && widget.carriedForward ? ' · from ${widget.carriedFromLabel}' : ''}',
            style: context.textTheme.labelSmall?.copyWith(color: soft, fontWeight: FontWeight.w600),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              if (widget.onRecordPayment != null && remaining != null && remaining >= 0.005)
                FilledButton.tonalIcon(
                  onPressed: widget.onRecordPayment,
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Record payment'),
                ),
              if (widget.onApplyAdvance != null && remaining != null && remaining >= 0.005)
                TextButton.icon(
                  onPressed: widget.onApplyAdvance,
                  icon: const Icon(Icons.savings_outlined, size: 16),
                  label: const Text('Use advance'),
                ),
              if (row.paymentId != null && widget.onRevertPayment != null && kind.isPayment)
                TextButton.icon(
                  onPressed: () => widget.onRevertPayment!(row.paymentId!),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('Revert payment'),
                ),
              if (widget.onOpen != null)
                TextButton.icon(onPressed: widget.onOpen, icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('View details')),
              if (widget.onDelete != null)
                TextButton.icon(
                  onPressed: widget.onDelete,
                  style: TextButton.styleFrom(foregroundColor: context.colors.error),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cycle reconciliation strip
// ---------------------------------------------------------------------------

/// "Amma owes you ₹2,666.67" + previous / added / received / current and any
/// advance — engine totals only, read in words.
class PersonCycleReconciliation extends StatelessWidget {
  const PersonCycleReconciliation({super.key, required this.statement, required this.personName});

  final PersonCycleStatement statement;
  final String personName;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final name = _firstName(personName);
    final strong = context.colors.onSurface;
    final soft = strong.withValues(alpha: 0.72);
    final dir = s.direction;
    final color = switch (dir) {
      StatementDirection.theyOwe => SettlementColors.receivable,
      StatementDirection.iOwe => SettlementColors.payable,
      StatementDirection.settled => SettlementColors.receivable,
    };
    final headline = switch (dir) {
      StatementDirection.theyOwe => '$name owes you',
      StatementDirection.iOwe => 'You owe $name',
      StatementDirection.settled => 'All settled',
    };
    String side(double signed) => signed.abs() < 0.005 ? '' : (signed > 0 ? ' · $name owes you' : ' · you owe $name');
    double applied(StatementCategory c) => s.rows.where((r) => r.category == c).fold(0.0, (t, r) => t + r.amount);
    final receivedApplied = applied(StatementCategory.received);
    final paidApplied = applied(StatementCategory.repaid);
    final advanceUsed = applied(StatementCategory.advanceApplied);
    final totalDue = s.previousPending + s.cycleActivity;

    Widget line(String label, double value, {String suffix = '', bool bold = false, Color? tone}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    style: context.textTheme.bodySmall?.copyWith(color: bold ? strong : soft, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
                    children: [TextSpan(text: suffix, style: context.textTheme.labelSmall?.copyWith(color: soft))],
                  ),
                ),
              ),
              Text(
                _money(value.abs()),
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: tone ?? strong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settlement · ${s.cycle.label}', style: context.textTheme.labelSmall?.copyWith(color: soft, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline.toUpperCase(), style: context.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              Text(
                _money(s.amount),
                style: context.textTheme.headlineMedium?.copyWith(
                  color: dir == StatementDirection.settled ? strong : color,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        line('Previous pending', s.previousPending, suffix: side(s.previousPending), tone: s.previousPending.abs() >= 0.005 ? SettlementColors.carried : null),
        line('Added this cycle', s.cycleActivity, suffix: side(s.cycleActivity)),
        Divider(height: 8, color: strong.withValues(alpha: 0.25)),
        line('Total due', totalDue, suffix: side(totalDue), bold: true),
        if (receivedApplied > 0 || paidApplied == 0) line('Received from $name', receivedApplied, tone: receivedApplied > 0 ? SettlementColors.receivable : null),
        if (paidApplied > 0) line('Paid to $name', paidApplied, tone: SettlementColors.receivable),
        if (advanceUsed > 0) line('Covered by advance', advanceUsed, tone: SettlementColors.advance),
        Divider(height: 10, thickness: 2, color: strong.withValues(alpha: 0.4)),
        line(dir == StatementDirection.settled ? 'SETTLED' : 'CURRENT PENDING', s.amount, bold: true, tone: color),
        if (s.cashReceived - receivedApplied >= 0.005)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${_money(s.cashReceived)} received from $name this cycle · ${_money(receivedApplied)} applied to what was due',
              style: context.textTheme.labelSmall?.copyWith(color: soft),
            ),
          ),
        if (s.advanceBalance.abs() >= 0.005)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: SettlementColors.advance.withValues(alpha: context.isDarkMode ? 0.2 : 0.12),
              border: const Border(left: BorderSide(color: SettlementColors.advance, width: 3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.advanceBalance < 0 ? 'Advance from $name' : 'Advance you paid $name',
                    style: context.textTheme.bodySmall?.copyWith(color: SettlementColors.advance, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _money(s.advanceBalance.abs()),
                  style: context.textTheme.bodySmall?.copyWith(color: SettlementColors.advance, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small parts
// ---------------------------------------------------------------------------

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.textTheme.labelSmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.65), fontWeight: FontWeight.w600)),
          Text(
            value,
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color ?? context.colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: context.isDarkMode ? 0.28 : 0.16), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          // Flexible + ellipsis: inside a Wrap the badge is bounded by the row width, so a long label
          // (e.g. a carried-from cycle) shortens instead of overflowing on a 360px phone.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label.toUpperCase(),
        style: context.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5),
      ),
    );
  }
}
