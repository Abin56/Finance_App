import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../../domain/transaction_type.dart';
import '../providers/transaction_providers.dart';

/// Full-screen "move money between two of my own accounts" flow — a real
/// primitive (two linked `Transaction`s sharing a `transferId`, posted via
/// `TransactionRepository.createTransferPair`), not just an expense tagged
/// "Transfer". Reachable both as a normal add-entry option and from the SMS
/// Inbox's "Transfer Between My Accounts" conversion.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key, this.smsPrefill});

  /// Set when opened from the SMS Inbox — seeds amount/date/note. The
  /// source account is guessed by the conversion router from the SMS's
  /// bank/card match where possible; the destination is always left for the
  /// user, since an SMS never states which of the user's own accounts money
  /// moved into.
  final SmsPrefill? smsPrefill;

  static Future<void> show(BuildContext context, {SmsPrefill? smsPrefill}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TransferScreen(smsPrefill: smsPrefill)),
    );
  }

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: widget.smsPrefill == null ? '' : widget.smsPrefill!.amount.toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(text: widget.smsPrefill?.note ?? '');
  late DateTime _dateTime = widget.smsPrefill?.dateTime ?? DateTime.now();
  late String? _sourceAccountId = widget.smsPrefill?.suggestedAccountId;
  String? _destinationAccountId;
  String? _categoryId;
  bool _isSaving = false;
  String? _sourceError;
  String? _destinationError;
  String? _categoryError;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(picked.year, picked.month, picked.day, _dateTime.hour, _dateTime.minute);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dateTime));
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(_dateTime.year, _dateTime.month, _dateTime.day, picked.hour, picked.minute);
    });
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState!.validate();
    setState(() {
      _sourceError = _sourceAccountId == null ? 'Select the account money left' : null;
      _destinationError = _destinationAccountId == null ? 'Select the account money arrived in' : null;
      _categoryError = _categoryId == null ? 'Select a category' : null;
    });
    if (!formValid || _sourceAccountId == null || _destinationAccountId == null || _categoryId == null) return;
    if (_sourceAccountId == _destinationAccountId) {
      setState(() => _destinationError = 'Choose a different account than the source');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(transactionRepositoryProvider);
      final (sourceLeg, _) = await repository.createTransferPair(
        amount: double.parse(_amountController.text.trim()),
        dateTime: _dateTime,
        sourceAccountId: _sourceAccountId!,
        destinationAccountId: _destinationAccountId!,
        categoryId: _categoryId!,
        notes: _noteController.text.trim(),
      );

      final smsPrefill = widget.smsPrefill;
      if (smsPrefill != null) {
        await ref.read(smsInboxItemsProvider.notifier).markImported(smsPrefill.smsId, linkedEntityId: sourceLeg.id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save transfer: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.expense));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Between Accounts'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text('Save', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: AppSizes.lg,
            right: AppSizes.lg,
            top: AppSizes.md,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount', style: context.textTheme.titleSmall),
              const SizedBox(height: AppSizes.xs),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee_rounded), isDense: true),
                style: context.textTheme.titleLarge,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load accounts: $error'),
                data: (accounts) {
                  final validSource = accounts.any((a) => a.id == _sourceAccountId) ? _sourceAccountId : null;
                  final validDestination =
                      accounts.any((a) => a.id == _destinationAccountId) ? _destinationAccountId : null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: validSource,
                        decoration: InputDecoration(labelText: 'From account', errorText: _sourceError),
                        items: [
                          for (final account in accounts)
                            DropdownMenuItem(value: account.id, child: Text(account.name)),
                        ],
                        onChanged: (value) => setState(() {
                          _sourceAccountId = value;
                          _sourceError = null;
                        }),
                      ),
                      const SizedBox(height: AppSizes.md),
                      DropdownButtonFormField<String>(
                        initialValue: validDestination,
                        decoration: InputDecoration(labelText: 'To account', errorText: _destinationError),
                        items: [
                          for (final account in accounts)
                            DropdownMenuItem(value: account.id, child: Text(account.name)),
                        ],
                        onChanged: (value) => setState(() {
                          _destinationAccountId = value;
                          _destinationError = null;
                        }),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String>(
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: InputDecoration(labelText: 'Category', errorText: _categoryError),
                items: [
                  for (final category in categories) DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() {
                  _categoryId = value;
                  _categoryError = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),
              Text('Date & Time', style: context.textTheme.titleSmall),
              const SizedBox(height: AppSizes.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: AppSizes.iconSm),
                      label: Text(_dateTime.fullDate),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time_outlined, size: AppSizes.iconSm),
                      label: Text(TimeOfDay.fromDateTime(_dateTime).format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.lg),
              PrimaryButton(label: 'Save Transfer', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.xs),
            ],
          ),
        ),
      ),
    );
  }
}
