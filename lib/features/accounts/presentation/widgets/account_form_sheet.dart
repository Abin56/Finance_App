import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
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
  late AccountType _type = widget.account?.type ?? AccountType.cash;
  late int _colorValue = widget.account?.colorValue ?? AppColors.categoryPalette.first.toARGB32();
  bool _isSaving = false;

  bool get _isEditing => widget.account != null;

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final repository = ref.read(accountRepositoryProvider);
    if (_isEditing) {
      await repository.editAccount(
        widget.account!,
        name: _nameController.text.trim(),
        type: _type,
        colorValue: _colorValue,
      );
    } else {
      await repository.createAccount(
        name: _nameController.text.trim(),
        type: _type,
        openingBalance: double.parse(_openingBalanceController.text.trim()),
        colorValue: _colorValue,
      );
    }

    if (mounted) Navigator.of(context).pop();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit account' : 'Add account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.lg),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Account name'),
              validator: Validators.required,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final type in AccountType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: AppSizes.md),
            TextFormField(
              controller: _openingBalanceController,
              enabled: !_isEditing,
              decoration: InputDecoration(
                labelText: 'Starting amount',
                helperText: _isEditing ? 'Starting amount can\'t be changed later' : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.amount,
            ),
            const SizedBox(height: AppSizes.md),
            Wrap(
              spacing: AppSizes.sm,
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
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(
              label: _isEditing ? 'Save changes' : 'Add account',
              isLoading: _isSaving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }
}
