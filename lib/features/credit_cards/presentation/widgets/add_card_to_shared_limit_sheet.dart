import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/bank_picker_sheet.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/card_network.dart';
import '../../domain/shared_credit_limit.dart';
import '../providers/credit_card_providers.dart';
import 'credit_card_visual.dart';

/// Preset card face colors — mirrors [CreditCardFormSheet]'s swatches so a
/// second physical card under the same limit gets the same one-tap picker.
const _cardThemeColors = <Color>[
  Color(0xFF1565C0), // blue
  Color(0xFF212121), // black
  Color(0xFF6A1B9A), // purple
  Color(0xFF2E7D32), // green
  Color(0xFFC62828), // red
  Color(0xFF78909C), // silver
  Color(0xFFB8860B), // gold
  Color(0xFF00695C), // teal
];

/// A focused "add another physical card" flow, reached only from inside a
/// [SharedCreditLimit] facility's own card — so unlike [CreditCardFormSheet]
/// it never asks whether the new card shares a limit (it already does, by
/// construction) and never asks for a credit limit of its own (the facility
/// supplies that). Just the physical card's own identity: network, last 4
/// digits, optional nickname/color, and its own bill/due dates, since each
/// physical card still gets its own statement.
class AddCardToSharedLimitSheet extends ConsumerStatefulWidget {
  const AddCardToSharedLimitSheet({super.key, required this.sharedLimit});

  final SharedCreditLimit sharedLimit;

  static Future<void> show(BuildContext context, {required SharedCreditLimit sharedLimit}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddCardToSharedLimitSheet(sharedLimit: sharedLimit),
    );
  }

  @override
  ConsumerState<AddCardToSharedLimitSheet> createState() => _AddCardToSharedLimitSheetState();
}

class _AddCardToSharedLimitSheetState extends ConsumerState<AddCardToSharedLimitSheet> {
  final _formKey = GlobalKey<FormState>();
  final _statementDayController = TextEditingController();
  final _paymentDueDayController = TextEditingController();
  final _lastFourDigitsController = TextEditingController()..addListener(() {});
  final _cardHolderNameController = TextEditingController();
  final _nicknameController = TextEditingController();

  String? _bankId;
  CardNetwork? _cardNetwork;
  int _colorValue = AppColors.primary.toARGB32();
  int? _colorAppliedByBank;
  bool _isSaving = false;

  String get _displayTitle {
    final nickname = _nicknameController.text.trim();
    if (nickname.isNotEmpty) return nickname;
    final last4 = _lastFourDigitsController.text.trim();
    return cardDisplayName(
      bank: BankRegistry.byId(_bankId),
      networkLabel: _cardNetwork?.label,
      last4: last4.isEmpty ? null : last4,
    );
  }

  @override
  void initState() {
    super.initState();
    // The facility's name is usually the bank name — prefill so most users
    // never have to open the bank picker at all.
    _bankId = BankRegistry.matchByName(widget.sharedLimit.name)?.id;
    if (_bankId != null) _colorValue = BankRegistry.byId(_bankId)!.primaryColor.toARGB32();
    _colorAppliedByBank = _colorValue;
  }

  @override
  void dispose() {
    _statementDayController.dispose();
    _paymentDueDayController.dispose();
    _lastFourDigitsController.dispose();
    _cardHolderNameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _pickBank() async {
    final picked = await BankPickerSheet.show(context, currentBankId: _bankId);
    if (picked == null) return;
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
      final statementDay = int.parse(_statementDayController.text.trim());
      final paymentDueDay = int.parse(_paymentDueDayController.text.trim());
      final lastFourDigits = _lastFourDigitsController.text.trim();
      final cardHolderName = _cardHolderNameController.text.trim();

      final account = await ref.read(accountRepositoryProvider).createAccount(
            name: _displayTitle,
            type: AccountType.card,
            openingBalance: 0,
            colorValue: _colorValue,
            bankId: _bankId,
          );
      await ref.read(creditCardRepositoryProvider).createCard(
            accountId: account.id,
            statementDay: statementDay,
            paymentDueDay: paymentDueDay,
            creditLimit: 0,
            cardNetwork: _cardNetwork,
            lastFourDigits: lastFourDigits.isEmpty ? null : lastFourDigits,
            cardHolderName: cardHolderName.isEmpty ? null : cardHolderName,
            sharedLimitId: widget.sharedLimit.id,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add card: $e')),
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
              Text('Add Another Physical Card', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.xs),
              Text(
                'This card will use the same approved credit limit, but will keep its own '
                'statement and transactions.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: AppSizes.lg),
              CreditCardVisual(
                title: _displayTitle,
                colorValue: _colorValue,
                bankId: _bankId,
                cardNetwork: _cardNetwork,
                lastFourDigits:
                    _lastFourDigitsController.text.trim().isEmpty ? null : _lastFourDigitsController.text.trim(),
                cardHolderName:
                    _cardHolderNameController.text.trim().isEmpty ? null : _cardHolderNameController.text.trim(),
              ),
              const SizedBox(height: AppSizes.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final color in _cardThemeColors)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSizes.sm),
                        child: GestureDetector(
                          onTap: () => setState(() => _colorValue = color.toARGB32()),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, Color.lerp(color, Colors.black, 0.4)!],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: _colorValue == color.toARGB32()
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                      ),
                    if (BankRegistry.byId(_bankId) != null)
                      TextButton(
                        onPressed: () => setState(() {
                          final color = BankRegistry.byId(_bankId)!.primaryColor.toARGB32();
                          _colorValue = color;
                          _colorAppliedByBank = color;
                        }),
                        child: const Text('Bank color'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),
              InkWell(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                onTap: _pickBank,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Bank'),
                  child: Row(
                    children: [
                      BankAvatar(bankId: _bankId, size: 28),
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
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: 'Card name (optional)',
                  helperText: 'A nickname like "Travel card" — otherwise named after the bank',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
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
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _cardHolderNameController,
                decoration: const InputDecoration(
                  labelText: 'Card holder name (optional)',
                  helperText: 'Name printed on the card, e.g. ABIN JOHN',
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _statementDayController,
                decoration: const InputDecoration(
                  labelText: 'Bill generated on',
                  helperText: 'The day each month this card\'s bill is generated (e.g. 17)',
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
              const SizedBox(height: AppSizes.lg),
              PrimaryButton(label: 'Add card', isLoading: _isSaving, onPressed: _save),
              const SizedBox(height: AppSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}
