import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/bank_picker_sheet.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/account.dart';
import '../../domain/account_type.dart';
import '../providers/account_providers.dart';

/// Bottom sheet for creating or editing an account. Opening balance can
/// only be set on creation — editing it later would silently rewrite
/// financial history, which the audit-trail design explicitly disallows.
class AccountFormSheet extends ConsumerStatefulWidget {
  const AccountFormSheet({super.key, this.account});

  final Account? account;

  static Future<void> show(BuildContext context, {Account? account}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountFormSheet(account: account),
    );
  }

  @override
  ConsumerState<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.account?.name);
  late final _openingBalanceController = TextEditingController(
    text: widget.account == null ? '0' : widget.account!.openingBalance.toStringAsFixed(2),
  );
  late final _accountHolderNameController = TextEditingController(text: widget.account?.accountHolderName);
  late final _notesController = TextEditingController(text: widget.account?.notes);
  late final _accountNumberLast4Controller = TextEditingController(text: widget.account?.accountNumberLast4)
    ..addListener(() => setState(() {}));
  final _openingBalanceFocusNode = FocusNode();
  late AccountType _type = widget.account?.type ?? AccountType.cash;
  late int _colorValue = widget.account?.colorValue ?? AppColors.categoryPalette.first.toARGB32();

  /// The bank picked for this account — resolved from the account's own
  /// [Account.bankId] if set, otherwise from a name match against the
  /// registry (the non-destructive fallback for pre-existing accounts).
  late String? _bankId =
      widget.account?.bankId ?? BankRegistry.matchByName(widget.account?.name ?? '')?.id;

  /// Tracks the color that was last applied automatically by picking a
  /// bank, so a later bank change only overwrites the swatch if the user
  /// hasn't manually picked a different one since.
  int? _colorAppliedByBank;
  bool _isSaving = false;

  bool get _isEditing => widget.account != null;

  /// Once a bank is picked for a bank/card-type account, its name is
  /// computed from the bank + last 4 digits rather than typed — "SBI" and
  /// the account number already identify it without asking the user for a
  /// redundant label. Cash/wallet/business/other accounts have no bank to
  /// compute from, so they keep the manual name field.
  bool get _isBankLinked =>
      (_type == AccountType.bank || _type == AccountType.card) && BankRegistry.byId(_bankId) != null;

  String get _computedName => bankAccountDisplayName(
        bank: BankRegistry.byId(_bankId)!,
        last4: _accountNumberLast4Controller.text.trim(),
      );

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    _accountHolderNameController.dispose();
    _notesController.dispose();
    _accountNumberLast4Controller.dispose();
    _openingBalanceFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickBank() async {
    final picked = await BankPickerSheet.show(context, currentBankId: _bankId);
    if (picked == null) return; // dismissed, no change
    final resolvedId = picked == BankRegistry.generic.id ? null : picked;
    setState(() {
      final bank = BankRegistry.byId(resolvedId);
      if (bank != null && (_colorAppliedByBank == null || _colorValue == _colorAppliedByBank)) {
        _colorValue = bank.primaryColor.toARGB32();
        _colorAppliedByBank = _colorValue;
      }
      _bankId = resolvedId;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(accountRepositoryProvider);
      final accountNumberLast4 = _accountNumberLast4Controller.text.trim();
      final accountHolderName = _accountHolderNameController.text.trim();
      final notes = _notesController.text.trim();
      final name = _isBankLinked ? _computedName : _nameController.text.trim();
      if (_isEditing) {
        await repository.editAccount(
          widget.account!,
          name: name,
          type: _type,
          colorValue: _colorValue,
          bankId: _bankId,
          clearBankId: _bankId == null,
          accountHolderName: accountHolderName.isEmpty ? null : accountHolderName,
          clearAccountHolderName: accountHolderName.isEmpty,
          notes: notes.isEmpty ? null : notes,
          clearNotes: notes.isEmpty,
          accountNumberLast4: accountNumberLast4.isEmpty ? null : accountNumberLast4,
          clearAccountNumberLast4: accountNumberLast4.isEmpty,
        );
      } else {
        await repository.createAccount(
          name: name,
          type: _type,
          openingBalance: double.parse(_openingBalanceController.text.trim()),
          colorValue: _colorValue,
          bankId: _bankId,
          accountHolderName: accountHolderName.isEmpty ? null : accountHolderName,
          notes: notes.isEmpty ? null : notes,
          accountNumberLast4: accountNumberLast4.isEmpty ? null : accountNumberLast4,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save account: $e')),
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
              Text(
                _isEditing ? 'Edit account' : 'Add account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSizes.lg),
              DropdownButtonFormField<AccountType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final type in AccountType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              if (_type == AccountType.bank || _type == AccountType.card) ...[
                const SizedBox(height: AppSizes.md),
                InkWell(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  onTap: _pickBank,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Bank'),
                    child: Row(
                      children: [
                        BankAvatar(bankId: _bankId, fallbackName: _nameController.text, size: 28),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: Text(
                            BankRegistry.byId(_bankId)?.name ?? 'Select bank (optional)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
                if (_isBankLinked)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSizes.xs, left: AppSizes.md),
                    child: Text(
                      'Shown as "$_computedName"',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              if (!_isBankLinked) ...[
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Account name'),
                  validator: Validators.required,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _openingBalanceFocusNode.requestFocus(),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _openingBalanceController,
                focusNode: _openingBalanceFocusNode,
                enabled: !_isEditing,
                decoration: InputDecoration(
                  labelText: 'Starting amount',
                  helperText: _isEditing ? 'Starting amount can\'t be changed later' : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: AppSizes.sm,
                      runSpacing: AppSizes.sm,
                      children: [
                        for (final color in AppColors.categoryPalette)
                          GestureDetector(
                            onTap: () => setState(() => _colorValue = color.toARGB32()),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: color,
                              child: _colorValue == color.toARGB32()
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (BankRegistry.byId(_bankId) != null)
                    TextButton(
                      onPressed: () => setState(() {
                        final color = BankRegistry.byId(_bankId)!.primaryColor.toARGB32();
                        _colorValue = color;
                        _colorAppliedByBank = color;
                      }),
                      child: const Text('Reset to bank color'),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('More options (optional)'),
                  children: [
                    TextFormField(
                      controller: _accountHolderNameController,
                      decoration: const InputDecoration(labelText: 'Account holder name'),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _accountNumberLast4Controller,
                      decoration: const InputDecoration(
                        labelText: 'Account number (last 4 digits)',
                        prefixText: '•••• ',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                    ),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add account',
                isLoading: _isSaving,
                onPressed: _save,
              ),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
