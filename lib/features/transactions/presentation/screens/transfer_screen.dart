import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
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
  late String? _categoryId = widget.smsPrefill?.suggestedCategoryId;
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
        source: widget.smsPrefill == null ? null : 'sms',
      );

      await completeSmsImport(ref, smsPrefill: widget.smsPrefill, linkedEntityId: sourceLeg.id);
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
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Amount', style: context.textTheme.labelMedium),
                    const SizedBox(height: AppSizes.xs),
                    TextFormField(
                      controller: _amountController,
                      decoration: _premiumDecoration(context, prefixIcon: const Icon(Icons.currency_rupee_rounded)),
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: Validators.amount,
                    ),
                    const SizedBox(height: AppSizes.sm),
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
                              decoration: _premiumDecoration(context, label: 'From account', errorText: _sourceError),
                              style: Theme.of(context).textTheme.bodyMedium,
                              items: [
                                for (final account in accounts)
                                  DropdownMenuItem(value: account.id, child: Text(accountPickerLabel(account, creditCards))),
                              ],
                              onChanged: (value) => setState(() {
                                _sourceAccountId = value;
                                _sourceError = null;
                              }),
                            ),
                            const SizedBox(height: AppSizes.sm),
                            DropdownButtonFormField<String>(
                              initialValue: validDestination,
                              decoration: _premiumDecoration(context, label: 'To account', errorText: _destinationError),
                              style: Theme.of(context).textTheme.bodyMedium,
                              items: [
                                for (final account in accounts)
                                  DropdownMenuItem(value: account.id, child: Text(accountPickerLabel(account, creditCards))),
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
                    const SizedBox(height: AppSizes.sm),
                    DropdownButtonFormField<String>(
                      initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                      decoration: _premiumDecoration(context, label: 'Category', errorText: _categoryError),
                      style: Theme.of(context).textTheme.bodyMedium,
                      items: [
                        for (final category in categories) DropdownMenuItem(value: category.id, child: Text(category.name)),
                      ],
                      onChanged: (value) => setState(() {
                        _categoryId = value;
                        _categoryError = null;
                      }),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text('Date & Time', style: context.textTheme.labelMedium),
                    const SizedBox(height: AppSizes.xs),
                    Row(
                      children: [
                        Expanded(
                          child: _PremiumTapButton(onTap: _pickDate, icon: Icons.calendar_today_outlined, label: _dateTime.fullDate),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: _PremiumTapButton(
                            onTap: _pickTime,
                            icon: Icons.access_time_outlined,
                            label: TimeOfDay.fromDateTime(_dateTime).format(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _noteController,
                      decoration: _premiumDecoration(context, label: 'Note (optional)'),
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
            ),
            _BottomSaveBar(label: 'Save Transfer', isLoading: _isSaving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// The filled, borderless-until-focus field decoration every field on this
/// screen shares — same vocabulary as `AddExpenseScreen`'s
/// `_premiumDecoration`. [label] is left null for the Amount field, which
/// uses an external label above it (a large hero figure) instead of an
/// internal floating one.
InputDecoration _premiumDecoration(
  BuildContext context, {
  String? label,
  String? errorText,
  Widget? prefixIcon,
}) {
  final colors = context.colors;
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    prefixIcon: prefixIcon,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
    filled: true,
    fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.6),
    ),
  );
}

/// A filled icon+label tap button — the premium replacement for
/// [OutlinedButton.icon], used for the Date/Time pickers.
class _PremiumTapButton extends StatelessWidget {
  const _PremiumTapButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSizes.iconSm, color: colors.primary),
              const SizedBox(width: AppSizes.xs),
              Flexible(
                child: Text(
                  label,
                  style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The persistent bottom action bar — pinned below the scroll instead of
/// living at its end, matching `AddExpenseScreen`'s `_BottomSaveBar`.
class _BottomSaveBar extends StatelessWidget {
  const _BottomSaveBar({required this.label, required this.isLoading, required this.onPressed});

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.sm, AppSizes.lg, AppSizes.sm),
        child: PrimaryButton(label: label, isLoading: isLoading, onPressed: onPressed),
      ),
    );
  }
}
