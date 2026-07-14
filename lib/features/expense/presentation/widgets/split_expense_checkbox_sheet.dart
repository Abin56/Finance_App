import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../data/expense_repository.dart';
import '../../domain/expense.dart';
import '../../domain/split_type.dart';
import '../providers/expense_providers.dart';

/// Figma "Split Expense" (frame 5) — a Cancel/Save modal that re-splits an
/// existing expense across a checkbox-driven people list. The total is fixed
/// (read-only, [Expense.totalAmount]); "You (Paid)" is the payer's own share,
/// toggled by a checkbox, and each checked person's share is computed
/// (Equal) or typed (Custom). Saves via [ExpenseRepository.resplitExpense],
/// which regenerates the schedule/installments/ledger — only allowed before
/// any payment has been collected (the repository enforces that).
class SplitExpenseCheckboxSheet extends ConsumerStatefulWidget {
  const SplitExpenseCheckboxSheet({super.key, required this.expense});

  final Expense expense;

  /// Resolves to `true` only when the expense was re-split, so callers show a
  /// success confirmation only on an actual save (not on cancel/back).
  static Future<bool?> show(BuildContext context, {required Expense expense}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => SplitExpenseCheckboxSheet(expense: expense)),
    );
  }

  @override
  ConsumerState<SplitExpenseCheckboxSheet> createState() => _SplitExpenseCheckboxSheetState();
}

/// One selectable person row's state — whether they're included in the split
/// and (for Custom) their typed share.
class _PersonRow {
  _PersonRow({required this.person, required this.checked, double share = 0}) {
    valueController.text = share > 0 ? share.toStringAsFixed(2) : '';
  }

  final Person person;
  bool checked;
  final TextEditingController valueController = TextEditingController();

  void dispose() => valueController.dispose();
}

class _SplitExpenseCheckboxSheetState extends ConsumerState<SplitExpenseCheckboxSheet> {
  SplitType _splitType = SplitType.equal;
  bool _includeMe = true;
  final _meValueController = TextEditingController();
  late List<_PersonRow> _rows;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Seed from the expense's current participants: everyone already on it
    // starts checked, "Me" reflects whether a Me participant exists.
    final people = ref.read(peopleStreamProvider).value ?? const <Person>[];
    final currentPersonIds = {
      for (final p in widget.expense.participants)
        if (!p.isMe && p.personId != null) p.personId!,
    };
    _includeMe = widget.expense.meParticipant != null;
    _rows = [
      for (final person in people)
        _PersonRow(person: person, checked: currentPersonIds.contains(person.id)),
    ];
  }

  @override
  void dispose() {
    _meValueController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  int get _checkedCount => _rows.where((r) => r.checked).length + (_includeMe ? 1 : 0);

  /// Live Equal-mode share per included head (Me + checked people).
  double get _equalShare => _checkedCount == 0 ? 0 : widget.expense.totalAmount / _checkedCount;

  /// "You will receive" — the sum of the checked *other* people's shares
  /// (excludes Me), matching the Contact Ledger metric of the same name.
  double get _youWillReceive {
    if (_splitType == SplitType.equal) {
      return _rows.where((r) => r.checked).length * _equalShare;
    }
    return _rows
        .where((r) => r.checked)
        .fold(0.0, (sum, r) => sum + (double.tryParse(r.valueController.text.trim()) ?? 0));
  }

  double _shareFor(_PersonRow row) {
    if (!row.checked) return 0;
    if (_splitType == SplitType.equal) return _equalShare;
    return double.tryParse(row.valueController.text.trim()) ?? 0;
  }

  List<ExpenseParticipantInput> _buildInputs() {
    return [
      if (_includeMe)
        ExpenseParticipantInput(
          name: 'Me',
          isMe: true,
          value: _splitType == SplitType.equal ? _equalShare : double.tryParse(_meValueController.text.trim()),
        ),
      for (final row in _rows)
        if (row.checked)
          ExpenseParticipantInput(
            personId: row.person.id,
            name: row.person.name,
            value: _splitType == SplitType.equal ? _equalShare : double.tryParse(row.valueController.text.trim()),
          ),
    ];
  }

  Future<void> _save() async {
    if (_rows.where((r) => r.checked).isEmpty) {
      setState(() => _error = 'Choose at least one person to share with');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(expenseRepositoryProvider).resplitExpense(
            expense: widget.expense,
            splitType: _splitType,
            participantInputs: _buildInputs(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not split expense: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showValue = _splitType == SplitType.custom;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        leadingWidth: 80,
        title: const Text('Split Expense'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text('Save', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Amount', style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
                Text(
                  CurrencyFormatter.instance.format(widget.expense.totalAmount),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Split Type', style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.sm),
          SegmentedButton<SplitType>(
            segments: const [
              ButtonSegment(value: SplitType.equal, label: Text('Equal')),
              ButtonSegment(value: SplitType.custom, label: Text('Custom')),
            ],
            selected: {_splitType},
            onSelectionChanged: (selection) => setState(() => _splitType = selection.first),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('People', style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.sm),
          _MeRow(
            included: _includeMe,
            share: _splitType == SplitType.equal
                ? (_includeMe ? _equalShare : 0)
                : (double.tryParse(_meValueController.text.trim()) ?? 0),
            showValue: showValue,
            valueController: _meValueController,
            onChanged: (value) => setState(() => _includeMe = value),
            onValueChanged: () => setState(() {}),
          ),
          for (final row in _rows)
            _PersonCheckRow(
              row: row,
              share: _shareFor(row),
              showValue: showValue,
              onChanged: (value) => setState(() => row.checked = value),
              onValueChanged: () => setState(() {}),
            ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('You will receive', style: context.textTheme.bodyMedium),
                Text(
                  CurrencyFormatter.instance.format(_youWillReceive),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: context.colors.primary),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSizes.sm),
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: context.colors.errorContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              child: Text(_error!, style: TextStyle(color: context.colors.onErrorContainer)),
            ),
          ],
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
                    'After splitting, each person will have their own share and you can collect separately.',
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MeRow extends StatelessWidget {
  const _MeRow({
    required this.included,
    required this.share,
    required this.showValue,
    required this.valueController,
    required this.onChanged,
    required this.onValueChanged,
  });

  final bool included;
  final double share;
  final bool showValue;
  final TextEditingController valueController;
  final ValueChanged<bool> onChanged;
  final VoidCallback onValueChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          const PersonAvatar(name: 'Me', colorValue: 0xFF5B5FEF, radius: 18),
          const SizedBox(width: AppSizes.md),
          const Expanded(child: Text('You (Paid)')),
          if (showValue && included)
            SizedBox(
              width: 90,
              child: TextField(
                controller: valueController,
                decoration: const InputDecoration(isDense: true, prefixText: '₹'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onValueChanged(),
              ),
            )
          else
            Text(
              CurrencyFormatter.instance.format(share),
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          const SizedBox(width: AppSizes.sm),
          Checkbox(value: included, onChanged: (v) => onChanged(v ?? false)),
        ],
      ),
    );
  }
}

class _PersonCheckRow extends StatelessWidget {
  const _PersonCheckRow({
    required this.row,
    required this.share,
    required this.showValue,
    required this.onChanged,
    required this.onValueChanged,
  });

  final _PersonRow row;
  final double share;
  final bool showValue;
  final ValueChanged<bool> onChanged;
  final VoidCallback onValueChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        children: [
          PersonAvatar(name: row.person.name, colorValue: row.person.avatarColorValue, radius: 18),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Text(row.person.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (showValue && row.checked)
            SizedBox(
              width: 90,
              child: TextField(
                controller: row.valueController,
                decoration: const InputDecoration(isDense: true, prefixText: '₹'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onValueChanged(),
              ),
            )
          else
            Text(
              CurrencyFormatter.instance.format(share),
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          const SizedBox(width: AppSizes.sm),
          Checkbox(value: row.checked, onChanged: (v) => onChanged(v ?? false)),
        ],
      ),
    );
  }
}
