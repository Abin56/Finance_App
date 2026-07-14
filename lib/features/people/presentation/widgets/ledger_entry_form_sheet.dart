import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/ledger_entry_type.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';

/// Bottom sheet for appending a new ledger entry to a person's timeline.
/// Ledger entries are append-only — this sheet only ever creates, never
/// edits, matching [LedgerRepository]'s API.
class LedgerEntryFormSheet extends ConsumerStatefulWidget {
  const LedgerEntryFormSheet({super.key, required this.person});

  final Person person;

  static Future<void> show(BuildContext context, Person person) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LedgerEntryFormSheet(person: person),
    );
  }

  @override
  ConsumerState<LedgerEntryFormSheet> createState() => _LedgerEntryFormSheetState();
}

class _LedgerEntryFormSheetState extends ConsumerState<LedgerEntryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  LedgerEntryType _type = LedgerEntryType.gave;
  DateTime _date = DateTime.now();
  bool _isSaving = false;

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(ledgerRepositoryProvider(widget.person.id));
      final rawAmount = double.parse(_amountController.text.trim());

      await repository.addEntry(
        widget.person,
        type: _type,
        amount: rawAmount.abs(),
        date: _date,
        note: _noteController.text.trim(),
        increasesBalance: rawAmount >= 0,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add entry: $e')),
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
              Text('Add entry for ${widget.person.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              DropdownButtonFormField<LedgerEntryType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                selectedItemBuilder: (context) => [
                  for (final type in LedgerEntryType.values)
                    Align(alignment: Alignment.centerLeft, child: Text(type.label)),
                ],
                items: [
                  for (final type in LedgerEntryType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(type.label),
                            Text(
                              type.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  helperText: _type.isSignedByUser
                      ? 'A plus (+) adds to what they owe you, a minus (-) reduces it'
                      : null,
                ),
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                  signed: _type.isSignedByUser,
                ),
                validator: _type.isSignedByUser ? Validators.signedAmount : Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                label: Text(_date.fullDate),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(label: 'Add entry', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
