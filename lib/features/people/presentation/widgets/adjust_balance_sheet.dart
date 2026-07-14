import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/ledger_entry_type.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';

enum _AdjustmentDirection { increase, decrease }

/// Task 2's "correct a person's pending balance" flow — a focused sheet
/// purpose-built for the two-field correction the spec asks for (amount +
/// required reason), rather than the general-purpose
/// [LedgerEntryFormSheet]'s five-type picker. Posts a plain
/// [LedgerEntryType.adjustment] `LedgerEntry` via the existing
/// `LedgerRepository.addEntry` — never writes `Person.currentBalance`
/// directly, so the full audit trail (who/when/why) always exists.
class AdjustBalanceSheet extends ConsumerStatefulWidget {
  const AdjustBalanceSheet({super.key, required this.person});

  final Person person;

  static Future<void> show(BuildContext context, Person person) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AdjustBalanceSheet(person: person),
    );
  }

  @override
  ConsumerState<AdjustBalanceSheet> createState() => _AdjustBalanceSheetState();
}

class _AdjustBalanceSheetState extends ConsumerState<AdjustBalanceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  _AdjustmentDirection _direction = _AdjustmentDirection.increase;
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(ledgerRepositoryProvider(widget.person.id));
      await repository.addEntry(
        widget.person,
        type: LedgerEntryType.adjustment,
        amount: double.parse(_amountController.text.trim()),
        date: _date,
        note: _reasonController.text.trim(),
        increasesBalance: _direction == _AdjustmentDirection.increase,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not correct balance: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Correct Balance', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Amount Left: ${CurrencyFormatter.instance.format(widget.person.currentBalance.abs())}'
                '${widget.person.currentBalance == 0 ? '' : widget.person.currentBalance > 0 ? ' (they owe you)' : ' (you owe them)'}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSizes.lg),
              SegmentedButton<_AdjustmentDirection>(
                segments: const [
                  ButtonSegment(
                    value: _AdjustmentDirection.increase,
                    label: Text('Add Amount'),
                    icon: Icon(Icons.add_rounded),
                  ),
                  ButtonSegment(
                    value: _AdjustmentDirection.decrease,
                    label: Text('Reduce Amount'),
                    icon: Icon(Icons.remove_rounded),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (selection) => setState(() => _direction = selection.first),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                label: Text(_date.fullDate),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: Validators.required,
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(label: 'Save correction', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
