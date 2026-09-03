import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/bank_picker_sheet.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/inputs/chip_selector.dart';
import '../../../../shared/widgets/inputs/color_swatch_picker.dart';
import '../../../../shared/widgets/section_label.dart';
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
      // The sheet renders its own banded header with a close button (see
      // SectionedFormSheet below) — a drag handle on top of that would be a
      // second, redundant "how do I close this" affordance.
      showDragHandle: false,
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
    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _isEditing ? 'Edit Account' : 'Add an Account',
        description: _isEditing ? null : 'A few details to start tracking balances and transactions.',
        accentColor: Color(_colorValue),
        confirmLabel: _isEditing ? 'Save Changes' : 'Add Account',
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionLabel('Account Details'),
            const SizedBox(height: AppSizes.sm),
            ChipSelector<AccountType>(
              options: [
                for (final type in AccountType.values)
                  ChipOption(value: type, label: type.label, icon: type.icon),
              ],
              value: _type,
              onChanged: (value) => setState(() => _type = value),
            ),
            if (_type == AccountType.bank || _type == AccountType.card) ...[
              const SizedBox(height: AppSizes.sm),
              _PremiumTapRow(
                onTap: _pickBank,
                child: Row(
                  children: [
                    BankLogo(bankId: _bankId, fallbackName: _nameController.text, size: 28),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(
                        BankRegistry.byId(_bankId)?.name ?? 'Select bank (optional)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                  ],
                ),
              ),
              if (_isBankLinked)
                Padding(
                  padding: const EdgeInsets.only(top: AppSizes.xs, left: AppSizes.sm),
                  child: Text(
                    'Shown as "$_computedName"',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (!_isBankLinked) ...[
              const SizedBox(height: AppSizes.sm),
              TextFormField(
                controller: _nameController,
                decoration: _premiumDecoration(context, label: 'Account name'),
                style: Theme.of(context).textTheme.bodyMedium,
                validator: Validators.required,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _openingBalanceFocusNode.requestFocus(),
              ),
            ],
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _openingBalanceController,
              focusNode: _openingBalanceFocusNode,
              enabled: !_isEditing,
              decoration: _premiumDecoration(
                context,
                label: 'Starting amount',
                helperText: _isEditing ? 'Starting amount can\'t be changed later' : null,
              ),
              style: Theme.of(context).textTheme.bodyMedium,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.amount,
              textInputAction: TextInputAction.done,
            ),

            const SizedBox(height: AppSizes.md),
            const SectionLabel('Color'),
            const SizedBox(height: AppSizes.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ColorSwatchPicker(
                    value: Color(_colorValue),
                    onChanged: (color) => setState(() => _colorValue = color.toARGB32()),
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

            const SizedBox(height: AppSizes.md),
            const SectionLabel('Additional Info (optional)'),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _accountHolderNameController,
              decoration: _premiumDecoration(context, label: 'Account holder name'),
              style: Theme.of(context).textTheme.bodyMedium,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _accountNumberLast4Controller,
              decoration: _premiumDecoration(context, label: 'Account number (last 4 digits)', prefixText: '•••• '),
              style: Theme.of(context).textTheme.bodyMedium,
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _notesController,
              decoration: _premiumDecoration(context, label: 'Notes'),
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// The filled, borderless-until-focus field decoration every field on this
/// sheet shares — same vocabulary as `SplitExpenseFormSheet`'s
/// `_premiumDecoration`.
InputDecoration _premiumDecoration(
  BuildContext context, {
  required String label,
  String? helperText,
  String? prefixText,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    helperText: helperText,
    prefixText: prefixText,
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

/// A filled, tappable row — the premium replacement for wrapping a plain
/// [InkWell] around an [InputDecorator], used for the Bank picker so it
/// shares the same surface treatment as this sheet's text fields.
class _PremiumTapRow extends StatelessWidget {
  const _PremiumTapRow({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
          child: child,
        ),
      ),
    );
  }
}
