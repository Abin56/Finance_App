import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/statement.dart';
import '../providers/credit_card_providers.dart';

/// Bottom sheet for recording a payment toward a [Statement] — reuses the
/// Bills payment-sheet shape (amount/date/source account/note), plus a
/// category picker since [StatementPaymentRepository.recordPayment] posts a
/// real outgoing [Transaction] that needs one, unlike a bill payment whose
/// source account is implicit.
class RecordStatementPaymentSheet extends ConsumerStatefulWidget {
  const RecordStatementPaymentSheet({super.key, required this.cardId, required this.statement});

  final String cardId;
  final Statement statement;

  static Future<void> show(BuildContext context, {required String cardId, required Statement statement}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordStatementPaymentSheet(cardId: cardId, statement: statement),
    );
  }

  @override
  ConsumerState<RecordStatementPaymentSheet> createState() => _RecordStatementPaymentSheetState();
}

class _RecordStatementPaymentSheetState extends ConsumerState<RecordStatementPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(text: widget.statement.remainingAmount.toStringAsFixed(2));
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _categoryId;
  String? _accountError;
  String? _categoryError;
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
    final formValid = _formKey.currentState!.validate();
    setState(() {
      _accountError = _accountId == null ? 'Select an account' : null;
      _categoryError = _categoryId == null ? 'Select a category' : null;
    });
    if (!formValid || _accountId == null || _categoryId == null) return;

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(
        statementPaymentRepositoryProvider((cardId: widget.cardId, statementId: widget.statement.id)),
      );
      await repository.recordPayment(
        widget.statement,
        amount: double.parse(_amountController.text.trim()),
        date: _date,
        sourceAccountId: _accountId!,
        categoryId: _categoryId!,
        note: _noteController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record payment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.expense));

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
              Text('Pay statement', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.xs),
              Text(
                '${CurrencyFormatter.instance.format(widget.statement.remainingAmount)} left to pay',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load accounts: $error'),
                data: (accounts) {
                  final validId = accounts.any((a) => a.id == _accountId) ? _accountId : null;
                  return DropdownButtonFormField<String>(
                    initialValue: validId,
                    decoration: InputDecoration(labelText: 'Pay from', errorText: _accountError),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(value: account.id, child: Text(account.name)),
                    ],
                    onChanged: (value) => setState(() {
                      _accountId = value;
                      _accountError = null;
                    }),
                  );
                },
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<String>(
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: InputDecoration(labelText: 'Category', errorText: _categoryError),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() {
                  _categoryId = value;
                  _categoryError = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickDate,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(label: 'Record payment', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
