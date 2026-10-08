import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/domain/category_type.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../data/person_payment_repository.dart';
import '../../domain/person.dart';
import '../../domain/person_cycle_statement.dart';
import '../../domain/person_payment.dart';
import '../providers/person_payment_providers.dart';
import '../providers/person_pending_participants_providers.dart';

/// What an existing payment looked like — for editing it.
class RecordPaymentInitial {
  const RecordPaymentInitial({
    required this.paymentId,
    required this.direction,
    required this.amount,
    required this.accountId,
    required this.date,
    required this.lines,
    this.advance = 0,
  });
  final String paymentId;
  final PaymentDirection direction;
  final double amount;
  final String? accountId;
  final DateTime date;

  /// Obligation key → amount this payment put on it.
  final Map<String, double> lines;
  final double advance;
}

/// Record Payment — one real payment between me and a person, allocated
/// across the obligations it pays. Every figure shown comes from
/// [allocatePayment] (the same rule the web app uses); saving writes exactly
/// those lines through [PersonPaymentRepository] in one atomic transaction.
/// Extra money is never silently classified: it must be kept as advance,
/// recorded as income, or put on another obligation by selecting it.
class RecordPaymentSheet extends ConsumerStatefulWidget {
  const RecordPaymentSheet({super.key, required this.person, this.preselectKey, this.initial});

  final Person person;
  final String? preselectKey;
  final RecordPaymentInitial? initial;

  static Future<void> show(BuildContext context, Person person, {String? preselectKey, RecordPaymentInitial? initial}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecordPaymentSheet(person: person, preselectKey: preselectKey, initial: initial),
    );
  }

  @override
  ConsumerState<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

enum _ExtraChoice { advance, income }

class _RecordPaymentSheetState extends ConsumerState<RecordPaymentSheet> {
  final _amount = TextEditingController();
  final _incomeDescription = TextEditingController();
  final _manualControllers = <String, TextEditingController>{};
  PaymentDirection? _direction;
  Set<String>? _selected;
  bool _manual = false;
  String? _accountId;
  DateTime _date = DateTime.now();
  _ExtraChoice? _extraChoice;
  String? _incomeCategoryId;
  bool _saving = false;
  String? _error;

  String get _first => widget.person.name.trim().split(RegExp(r'\s+')).first;
  String _money(double v) => CurrencyFormatter.instance.format(v);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _direction = i.direction;
      _amount.text = i.amount.toStringAsFixed(2);
      _accountId = i.accountId;
      _date = i.date;
      _selected = i.lines.keys.toSet();
      if (i.advance > 0) _extraChoice = _ExtraChoice.advance;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _incomeDescription.dispose();
    for (final c in _manualControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(personStatementSourcesProvider(widget.person.id));
    // When editing, this payment's own lines are open again (it is reverted in the same write).
    final payable = sources == null
        ? const <PayableObligation>[]
        : buildPayableObligations(
            sources,
            ref.watch(personSplitParticipantsProvider(widget.person.id)),
            reopen: widget.initial?.lines ?? const {},
          );
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];

    // Direction: from the row the sheet was opened for, else from who owes whom right now.
    final preselected = payable.where((p) => p.obligation.key == widget.preselectKey).firstOrNull;
    final pending = sources?.allTime().currentPending ?? 0;
    final direction = _direction ??
        (preselected != null
            ? (preselected.obligation.side == ObligationSide.iOwe ? PaymentDirection.iPaid : PaymentDirection.theyPaid)
            : (pending < 0 ? PaymentDirection.iPaid : PaymentDirection.theyPaid));
    final side = sideForDirection(direction);
    final options = payable.where((p) => p.obligation.side == side).toList();
    final selected = _selected ?? (preselected != null ? {preselected.obligation.key} : options.map((o) => o.obligation.key).toSet());
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final manual = _manual
        ? {for (final k in selected) k: double.tryParse(_manualControllers[k]?.text.trim() ?? '') ?? 0.0}
        : null;
    final alloc = allocatePayment(
      obligations: options.map((o) => o.obligation).toList(),
      selectedKeys: selected,
      amount: amount,
      manual: manual,
    );
    final resolution = alloc.extra > paymentEpsilon
        ? switch (_extraChoice) {
            _ExtraChoice.advance => const KeepAsAdvance(),
            _ExtraChoice.income => RecordAsIncome(categoryId: _incomeCategoryId ?? '', description: _incomeDescription.text),
            null => null,
          }
        : null;
    final accountId = _accountId ?? (accounts.isNotEmpty ? accounts.first.id : null);
    final blocker = paymentBlocker(direction: direction, amount: amount, allocation: alloc, resolution: resolution, accountId: accountId);
    final lineByKey = {for (final l in alloc.lines) l.key: l};
    final incomeCategories = categories.where((c) => c.type != CategoryType.expense && !c.isDeleted).toList();
    final unselected = options.where((o) => !selected.contains(o.obligation.key)).toList();
    final theyPaid = direction == PaymentDirection.theyPaid;
    final accent = theyPaid ? AppColors.income : AppColors.expense;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.xs),
          child: Text(t.toUpperCase(),
              style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.colors.onSurfaceVariant)),
        );

    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusXs),
      borderSide: BorderSide(color: context.colors.outline),
    );
    InputDecoration field(String hint, {String? prefix}) => InputDecoration(
          isDense: true,
          hintText: hint,
          prefixText: prefix,
          border: outline,
          enabledBorder: outline,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (context, scroll) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.md),
                children: [
                  Text(widget.initial == null ? 'Record payment — ${widget.person.name}' : 'Edit payment — ${widget.person.name}',
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    alloc.selectedTotal > 0 ? 'Outstanding selected ${_money(alloc.selectedTotal)}' : 'Nothing selected yet',
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSizes.md),
                  SegmentedButton<PaymentDirection>(
                    segments: [
                      ButtonSegment(value: PaymentDirection.theyPaid, label: Text('$_first paid me')),
                      ButtonSegment(value: PaymentDirection.iPaid, label: Text('I paid $_first')),
                    ],
                    selected: {direction},
                    onSelectionChanged: widget.initial != null
                        ? null
                        : (s) => setState(() {
                              _direction = s.first;
                              _selected = null;
                              _extraChoice = null;
                            }),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          label(theyPaid ? 'Amount received' : 'Amount paid'),
                          TextField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            decoration: field('0.00', prefix: '₹ '),
                            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            onChanged: (_) => setState(() {}),
                          ),
                        ]),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Date'),
                        OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now().add(const Duration(days: 366)),
                            );
                            if (picked != null) setState(() => _date = picked);
                          },
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          child: Text(StatementCycle.formatDate(_date, withYear: true)),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  label(theyPaid ? 'Received into' : 'Paid from'),
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    isExpanded: true,
                    decoration: field('Choose account'),
                    items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _accountId = v),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Row(children: [
                    Expanded(child: label('Apply payment to')),
                    if (options.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _selected =
                            selected.length == options.length ? <String>{} : options.map((o) => o.obligation.key).toSet()),
                        child: Text(selected.length == options.length ? 'Clear' : 'Select all outstanding'),
                      ),
                  ]),
                  if (options.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                      child: Text(
                        theyPaid ? '$_first owes you nothing right now.' : 'You owe $_first nothing right now.',
                        style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    )
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: context.colors.outline),
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      ),
                      child: Column(children: [
                        for (var i = 0; i < options.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: context.colors.outlineVariant),
                          _ObligationTile(
                            option: options[i],
                            checked: selected.contains(options[i].obligation.key),
                            applied: lineByKey[options[i].obligation.key],
                            manualController: _manual ? _controllerFor(options[i].obligation.key) : null,
                            money: _money,
                            onChanged: (v) => setState(() {
                              final next = {...selected};
                              v ? next.add(options[i].obligation.key) : next.remove(options[i].obligation.key);
                              _selected = next;
                            }),
                            onManualChanged: () => setState(() {}),
                          ),
                        ],
                      ]),
                    ),
                  if (selected.length > 1)
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allocate manually'),
                      subtitle: Text(_manual ? 'Set each amount yourself' : 'Oldest first, automatically'),
                      value: _manual,
                      onChanged: (v) => setState(() => _manual = v),
                    ),
                  const SizedBox(height: AppSizes.md),
                  _Summary(
                    rows: [
                      ('Selected obligations', _money(alloc.selectedTotal), null),
                      ('Payment entered', _money(amount), null),
                      if (alloc.extra > paymentEpsilon)
                        ('Extra amount', _money(alloc.extra), AppColors.warning)
                      else
                        ('Remaining after this', _money(alloc.unpaid), alloc.unpaid > paymentEpsilon ? AppColors.warning : AppColors.success),
                    ],
                    status: switch (alloc.outcome) {
                      PaymentOutcome.full => 'Fully settles the selected obligations',
                      PaymentOutcome.partial => 'Partial payment',
                      PaymentOutcome.over => 'More than selected',
                      PaymentOutcome.none => null,
                    },
                  ),
                  if (alloc.extra > paymentEpsilon) ...[
                    const SizedBox(height: AppSizes.md),
                    Container(
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        border: Border.all(color: AppColors.warning),
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_money(alloc.extra)} is still unallocated',
                            style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('What is this extra amount for?', style: context.textTheme.bodySmall),
                        RadioGroup<_ExtraChoice>(
                          groupValue: _extraChoice,
                          onChanged: (v) => setState(() => _extraChoice = v),
                          child: Column(children: [
                            RadioListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: _ExtraChoice.advance,
                              title: Text(theyPaid ? 'Keep as advance from $_first' : 'Keep as advance paid to $_first'),
                              subtitle: const Text('Held against future obligations — not income'),
                            ),
                            if (theyPaid)
                              RadioListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _ExtraChoice.income,
                                title: const Text('Record as separate income'),
                                subtitle: const Text('No longer counts toward what they owe'),
                              ),
                          ]),
                        ),
                        if (_extraChoice == _ExtraChoice.income) ...[
                          DropdownButtonFormField<String>(
                            initialValue: _incomeCategoryId,
                            isExpanded: true,
                            decoration: field('Income category'),
                            items: [for (final c in incomeCategories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                            onChanged: (v) => setState(() => _incomeCategoryId = v),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          TextField(controller: _incomeDescription, decoration: field('Description / source')),
                        ],
                        if (unselected.isNotEmpty) ...[
                          const SizedBox(height: AppSizes.sm),
                          Text('Or apply it to another outstanding obligation:', style: context.textTheme.bodySmall),
                          Wrap(spacing: AppSizes.xs, children: [
                            for (final o in unselected)
                              ActionChip(
                                label: Text('${o.obligation.title} · ${_money(o.obligation.outstanding)}'),
                                onPressed: () => setState(() => _selected = {...selected, o.obligation.key}),
                              ),
                          ]),
                        ],
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            // Sticky actions — the blocker says exactly what is missing.
            Container(
              padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.sm, AppSizes.lg, AppSizes.md),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.outlineVariant))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_error != null || blocker != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.xs),
                    child: Text(_error ?? blocker!,
                        style: context.textTheme.bodySmall?.copyWith(color: _error != null ? AppColors.error : context.colors.onSurfaceVariant)),
                  ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                  onPressed: blocker != null || _saving
                      ? null
                      : () => _save(direction, amount, accountId!, alloc, resolution, options),
                  child: Text(_saving
                      ? 'Saving…'
                      : widget.initial != null
                          ? 'Save changes'
                          : theyPaid
                              ? 'Record ${_money(amount)} received'
                              : 'Record ${_money(amount)} paid'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  TextEditingController _controllerFor(String key) => _manualControllers.putIfAbsent(key, TextEditingController.new);

  Future<void> _save(
    PaymentDirection direction,
    double amount,
    String accountId,
    PaymentAllocation alloc,
    ExtraResolution? resolution,
    List<PayableObligation> options,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final routes = {for (final o in options) o.obligation.key: o.route};
      final input = RecordPaymentInput(
        direction: direction,
        amount: amount,
        date: _date,
        accountId: accountId,
        lines: [for (final l in alloc.lines) PaymentLine(key: l.key, amount: l.amount, route: routes[l.key]!)],
        extra: alloc.extra <= paymentEpsilon
            ? null
            : switch (resolution) {
                KeepAsAdvance() => AdvanceExtra(alloc.extra),
                RecordAsIncome(:final categoryId, :final description) =>
                  IncomeExtra(alloc.extra, categoryId: categoryId, description: description),
                null => null,
              },
      );
      final repo = await ref.read(personPaymentRepositoryProvider(widget.person.id).future);
      if (widget.initial != null) {
        await repo.editPayment(widget.person, widget.initial!.paymentId, input);
      } else {
        await repo.recordPayment(widget.person, input);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^\w*Exception:?\s*'), ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ObligationTile extends StatelessWidget {
  const _ObligationTile({
    required this.option,
    required this.checked,
    required this.applied,
    required this.manualController,
    required this.money,
    required this.onChanged,
    required this.onManualChanged,
  });
  final PayableObligation option;
  final bool checked;
  final AllocationLine? applied;
  final TextEditingController? manualController;
  final String Function(double) money;
  final ValueChanged<bool> onChanged;
  final VoidCallback onManualChanged;

  @override
  Widget build(BuildContext context) {
    final o = option.obligation;
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: AppSizes.xs),
        child: Row(children: [
          Checkbox(value: checked, onChanged: (v) => onChanged(v ?? false)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('${StatementCycle.formatDate(o.date)} · ${option.typeLabel}',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ]),
          ),
          if (manualController != null && checked)
            SizedBox(
              width: 96,
              child: TextField(
                controller: manualController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: InputDecoration(isDense: true, hintText: o.outstanding.toStringAsFixed(0), prefixText: '₹'),
                onChanged: (_) => onManualChanged(),
              ),
            )
          else
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(o.outstanding), style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (checked && applied != null)
                Text(applied!.remainingAfter > paymentEpsilon ? 'pays ${money(applied!.amount)}' : 'settled',
                    style: context.textTheme.labelSmall?.copyWith(
                        color: applied!.remainingAfter > paymentEpsilon ? AppColors.warning : AppColors.success, fontWeight: FontWeight.w700)),
            ]),
        ]),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.rows, this.status});
  final List<(String, String, Color?)> rows;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: context.textTheme.bodyMedium)),
              Text(r.$2, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: r.$3)),
            ]),
          ),
        if (status != null) ...[
          const SizedBox(height: AppSizes.xs),
          Align(alignment: Alignment.centerLeft, child: Text(status!, style: context.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ]),
    );
  }
}
