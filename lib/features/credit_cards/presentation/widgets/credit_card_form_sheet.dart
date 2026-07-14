import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/card_network.dart';
import '../../domain/credit_card_profile.dart';
import '../../domain/credit_card_status.dart';
import '../providers/credit_card_providers.dart';

/// Add / edit a [CreditCardProfile]. A credit card IS an [Account] of type
/// [AccountType.card] plus this profile. When **adding**, the user just types
/// a card name and this form creates that account for them in one step (no
/// need to pre-create it) — or links an existing unused card account if one
/// happens to exist. When **editing**, the linked account is fixed.
class CreditCardFormSheet extends ConsumerStatefulWidget {
  const CreditCardFormSheet({super.key, this.card});

  final CreditCardProfile? card;

  static Future<void> show(BuildContext context, {CreditCardProfile? card}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CreditCardFormSheet(card: card),
    );
  }

  @override
  ConsumerState<CreditCardFormSheet> createState() => _CreditCardFormSheetState();
}

class _CreditCardFormSheetState extends ConsumerState<CreditCardFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late final _statementDayController = TextEditingController(text: widget.card?.statementDay.toString() ?? '');
  late final _paymentDueDayController = TextEditingController(text: widget.card?.paymentDueDay.toString() ?? '');
  late final _creditLimitController = TextEditingController(text: widget.card?.creditLimit.toStringAsFixed(2) ?? '');
  late final _minimumDuePercentController = TextEditingController(
    text: widget.card?.minimumDuePercent?.toString() ?? '',
  );
  late final _lastFourDigitsController = TextEditingController(text: widget.card?.lastFourDigits ?? '');
  late final _annualFeeController = TextEditingController(
    text: widget.card == null || widget.card!.annualFee == 0 ? '' : widget.card!.annualFee.toStringAsFixed(2),
  );
  late final _joiningFeeController = TextEditingController(
    text: widget.card == null || widget.card!.joiningFee == 0 ? '' : widget.card!.joiningFee.toStringAsFixed(2),
  );
  late final _interestRateController = TextEditingController(
    text: widget.card?.interestRatePercent?.toString() ?? '',
  );
  late final _rewardNotesController = TextEditingController(text: widget.card?.rewardNotes ?? '');
  late final _autoDebitAccountController = TextEditingController(text: widget.card?.autoDebitAccount ?? '');

  /// Only used in create mode when the user chooses to link an already-existing
  /// (unused) card account instead of having a new one created for them.
  String? _linkedAccountId;
  late bool _autoPay = widget.card?.autoPay ?? false;
  late CreditCardStatus _status = widget.card?.status ?? CreditCardStatus.active;
  late CardNetwork? _cardNetwork = widget.card?.cardNetwork;
  bool _isSaving = false;

  bool get _isEditing => widget.card != null;

  @override
  void initState() {
    super.initState();
    // Prefill the name with the linked account's name so editing can rename it.
    final card = widget.card;
    if (card != null) {
      final account = (ref.read(accountsStreamProvider).value ?? const [])
          .where((a) => a.id == card.accountId)
          .firstOrNull;
      if (account != null) _nameController.text = account.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statementDayController.dispose();
    _paymentDueDayController.dispose();
    _creditLimitController.dispose();
    _minimumDuePercentController.dispose();
    _lastFourDigitsController.dispose();
    _annualFeeController.dispose();
    _joiningFeeController.dispose();
    _interestRateController.dispose();
    _rewardNotesController.dispose();
    _autoDebitAccountController.dispose();
    super.dispose();
  }

  double? _parseOptionalAmount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(creditCardRepositoryProvider);
      final minimumDuePercent = double.tryParse(_minimumDuePercentController.text.trim());
      final statementDay = int.parse(_statementDayController.text.trim());
      final paymentDueDay = int.parse(_paymentDueDayController.text.trim());
      final creditLimit = double.parse(_creditLimitController.text.trim());

      if (_isEditing) {
        // Rename the linked account if the name changed — that's what a card's
        // display name actually is (a card IS an account).
        final newName = _nameController.text.trim();
        final account = (ref.read(accountsStreamProvider).value ?? const [])
            .where((a) => a.id == widget.card!.accountId)
            .firstOrNull;
        if (account != null && newName.isNotEmpty && newName != account.name) {
          await ref.read(accountRepositoryProvider).editAccount(account, name: newName);
        }
        await repository.editCard(
          widget.card!,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          creditLimit: creditLimit,
          minimumDuePercent: minimumDuePercent,
          clearMinimumDuePercent: _minimumDuePercentController.text.trim().isEmpty,
          autoPay: _autoPay,
          status: _status,
          cardNetwork: _cardNetwork,
          lastFourDigits: _lastFourDigitsController.text.trim().isEmpty ? null : _lastFourDigitsController.text.trim(),
          annualFee: _parseOptionalAmount(_annualFeeController.text) ?? 0,
          joiningFee: _parseOptionalAmount(_joiningFeeController.text) ?? 0,
          interestRatePercent: _parseOptionalAmount(_interestRateController.text),
          rewardNotes: _rewardNotesController.text.trim().isEmpty ? null : _rewardNotesController.text.trim(),
          autoDebitAccount: _autoPay && _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
        );
      } else {
        // Use a linked existing card account if the user picked one; otherwise
        // create the card's account inline so "add a card" is a single step.
        var accountId = _linkedAccountId;
        if (accountId == null) {
          final account = await ref.read(accountRepositoryProvider).createAccount(
                name: _nameController.text.trim(),
                type: AccountType.card,
                openingBalance: 0,
                colorValue: AppColors.primary.toARGB32(),
              );
          accountId = account.id;
        }
        await repository.createCard(
          accountId: accountId,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          creditLimit: creditLimit,
          minimumDuePercent: minimumDuePercent,
          autoPay: _autoPay,
          cardNetwork: _cardNetwork,
          lastFourDigits: _lastFourDigitsController.text.trim().isEmpty ? null : _lastFourDigitsController.text.trim(),
          annualFee: _parseOptionalAmount(_annualFeeController.text) ?? 0,
          joiningFee: _parseOptionalAmount(_joiningFeeController.text) ?? 0,
          interestRatePercent: _parseOptionalAmount(_interestRateController.text),
          rewardNotes: _rewardNotesController.text.trim().isEmpty ? null : _rewardNotesController.text.trim(),
          autoDebitAccount: _autoPay && _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save card: $e')),
        );
      }
    }
  }

  String? _dayValidator(String? value) {
    final day = int.tryParse(value?.trim() ?? '');
    if (day == null || day < 1 || day > 31) return 'Enter a day between 1 and 31';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final existingCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final linkedAccountIds = existingCards.where((c) => c.id != widget.card?.id).map((c) => c.accountId).toSet();
    // Card-type accounts that aren't already tied to a card — only offered as
    // an optional shortcut, never as a required (and possibly empty) dropdown.
    final unusedCardAccounts =
        accounts.where((a) => a.type == AccountType.card && !linkedAccountIds.contains(a.id)).toList();

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
              Text(_isEditing ? 'Card Settings' : 'Add a credit card', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _nameController,
                enabled: _linkedAccountId == null,
                decoration: const InputDecoration(
                  labelText: 'Card name',
                  helperText: 'e.g. HDFC Millennia, Amazon Pay ICICI',
                ),
                textInputAction: TextInputAction.next,
                // Required, except when linking an existing account (create only).
                validator: (value) {
                  if (!_isEditing && _linkedAccountId != null) return null;
                  return Validators.required(value);
                },
              ),
              if (!_isEditing && unusedCardAccounts.isNotEmpty) ...[
                const SizedBox(height: AppSizes.md),
                DropdownButtonFormField<String?>(
                  initialValue: _linkedAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Or link an existing card account (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Create a new card')),
                    for (final account in unusedCardAccounts)
                      DropdownMenuItem<String?>(value: account.id, child: Text(account.name)),
                  ],
                  onChanged: (value) => setState(() => _linkedAccountId = value),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              if (_isEditing) ...[
                DropdownButtonFormField<CreditCardStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Card status',
                    helperText: 'Mark the card closed or cancelled once you stop using it.',
                  ),
                  items: [
                    for (final status in CreditCardStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Row(
                          children: [
                            Icon(status.icon, size: AppSizes.iconSm, color: status.color),
                            const SizedBox(width: AppSizes.sm),
                            Text(status.label),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _status = value ?? _status),
                ),
                const SizedBox(height: AppSizes.md),
              ],
              DropdownButtonFormField<CardNetwork?>(
                initialValue: _cardNetwork,
                decoration: const InputDecoration(labelText: 'Card network (optional)'),
                items: [
                  const DropdownMenuItem<CardNetwork?>(value: null, child: Text('Not set')),
                  for (final network in CardNetwork.values)
                    DropdownMenuItem(value: network, child: Text(network.label)),
                ],
                onChanged: (value) => setState(() => _cardNetwork = value),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _lastFourDigitsController,
                decoration: const InputDecoration(
                  labelText: 'Last 4 digits (optional)',
                  prefixText: '•••• ',
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _creditLimitController,
                decoration: const InputDecoration(
                  labelText: 'Credit limit',
                  helperText: 'Your total spending limit on this card',
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _statementDayController,
                decoration: const InputDecoration(
                  labelText: 'Bill generated on',
                  helperText: 'The day each month your card bill is generated (e.g. 17)',
                  suffixText: 'day of month',
                ),
                keyboardType: TextInputType.number,
                validator: _dayValidator,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _paymentDueDayController,
                decoration: const InputDecoration(
                  labelText: 'Payment due on',
                  helperText: 'The day next month you pay it (e.g. 5)',
                  suffixText: 'day of next month',
                ),
                keyboardType: TextInputType.number,
                validator: _dayValidator,
              ),
              const SizedBox(height: AppSizes.sm),
              Theme(
                // Strip the ExpansionTile's default dividers so it blends into
                // the form instead of looking like a separate section.
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('More options (optional)'),
                  children: [
                    TextFormField(
                      controller: _minimumDuePercentController,
                      decoration: const InputDecoration(
                        labelText: 'Minimum payment %',
                        helperText: 'The smallest part of your bill you must pay to avoid a late fee. Leave blank if unsure.',
                        suffixText: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _annualFeeController,
                      decoration: const InputDecoration(labelText: 'Annual fee'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _joiningFeeController,
                      decoration: const InputDecoration(labelText: 'Joining fee'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _interestRateController,
                      decoration: const InputDecoration(
                        labelText: 'Interest rate (%)',
                        helperText: 'For your reference only — not used in any calculation.',
                        suffixText: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextFormField(
                      controller: _rewardNotesController,
                      decoration: const InputDecoration(labelText: 'Reward / cashback notes'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto pay'),
                      subtitle: const Text('For your reference only — this app does not make payments automatically.'),
                      value: _autoPay,
                      onChanged: (value) => setState(() => _autoPay = value),
                    ),
                    if (_autoPay)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSizes.sm),
                        child: TextFormField(
                          controller: _autoDebitAccountController,
                          decoration: const InputDecoration(labelText: 'Auto debit account'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              PrimaryButton(label: _isEditing ? 'Save changes' : 'Add card', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
