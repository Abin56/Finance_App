import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/bank_picker_sheet.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/domain/account_type.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../domain/card_network.dart';
import '../../domain/credit_card_profile.dart';
import '../../domain/credit_card_status.dart';
import '../providers/credit_card_providers.dart';
import 'credit_card_visual.dart';

/// Preset card themes — the face colors offered as one-tap swatches; each
/// renders as a gradient derived from the single stored color value.
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

/// How this card's credit limit is sourced — chosen up front (add mode) or
/// changed inline (edit mode), replacing the old after-the-fact "Link Card"
/// workflow. Mirrors how a bank actually issues cards: a Visa/RuPay/
/// Mastercard variant is either its own facility or shares an existing one
/// from day one, never "linked" together later.
enum _LimitSource { standalone, newSharedLimit, existingSharedLimit }

/// A step title used at the top of each wizard page — bold headline plus a
/// short one-line explainer, matching the reference design's "3 Card
/// details / These details are specific to this card." pattern.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.title, required this.subtitle});

  final int step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
          child: Text(
            '$step',
            style: context.textTheme.labelLarge?.copyWith(color: colors.onPrimary, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: context.textTheme.bodyMedium?.copyWith(color: colors.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A slim segmented progress bar across the top of the wizard — [stepCount]
/// filled/unfilled pill segments, the CRED/Revolut-style stand-in for the
/// reference design's dotted step indicator.
class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.currentStep, required this.stepCount});

  final int currentStep;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (var i = 0; i < stepCount; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i <= currentStep ? colors.primary : colors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppSizes.radiusPill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single card-panel module — the wizard's core visual unit. Every group
/// of related fields sits inside one of these: a softly-shadowed, rounded,
/// theme-aware surface with generous internal padding, so a step reads as a
/// stack of distinct premium panels rather than one continuous scroll.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}

/// A calmer, filled-and-borderless text field — flat tinted background,
/// fully rounded corners, no visible outline until focus, where a thin
/// primary-colored ring appears. Mirrors CRED/Revolut's input styling more
/// closely than the app's default outlined [TextFormField] look. A drop-in
/// replacement: same controller/validator/decoration-adjacent API surface.
class _PremiumField extends StatelessWidget {
  const _PremiumField({
    required this.controller,
    required this.label,
    this.helperText,
    this.prefixIcon,
    this.prefixText,
    this.suffixText,
    this.keyboardType,
    this.maxLength,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final IconData? prefixIcon;
  final String? prefixText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final void Function(String)? onChanged;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLength: maxLength,
      validator: validator,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: AppSizes.iconSm),
        prefixText: prefixText,
        suffixText: suffixText,
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
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
      ),
    );
  }
}

/// A [_PremiumField]-styled dropdown — same flat filled look, so pickers
/// (network, status, shared-limit) don't visually break the field rhythm
/// set by every text input around them.
class _PremiumDropdown<T> extends StatelessWidget {
  const _PremiumDropdown({
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
    this.validator,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final String label;
  final void Function(T?) onChanged;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: colors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
      ),
    );
  }
}

/// One tappable network chip — the reference design's Visa/Mastercard/RuPay/
/// Amex grid replacing the old plain dropdown for this one choice.
class _NetworkChip extends StatelessWidget {
  const _NetworkChip({required this.network, required this.selected, required this.onTap});

  final CardNetwork network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.primaryContainer.withValues(alpha: 0.35) : colors.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(color: selected ? colors.primary : colors.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.credit_card_rounded, size: AppSizes.iconSm, color: selected ? colors.primary : colors.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                network.label,
                style: context.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.primary : colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit a [CreditCardProfile]. A credit card IS an [Account] of type
/// [AccountType.card] plus this profile. When **adding**, the user just types
/// a card name and this form creates that account for them in one step (no
/// need to pre-create it) — or links an existing unused card account if one
/// happens to exist. When **editing**, the linked account is fixed.
///
/// Presented as a full-screen, 4-step wizard (Card basics → Credit limit →
/// Details & billing → Customize) rather than one long scroll, so the long
/// form reads like a guided setup instead of a wall of fields.
class CreditCardFormSheet extends ConsumerStatefulWidget {
  const CreditCardFormSheet({super.key, this.card});

  final CreditCardProfile? card;

  static Future<void> show(BuildContext context, {CreditCardProfile? card}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreditCardFormSheet(card: card), fullscreenDialog: true),
    );
  }

  @override
  ConsumerState<CreditCardFormSheet> createState() => _CreditCardFormSheetState();
}

class _CreditCardFormSheetState extends ConsumerState<CreditCardFormSheet> {
  static const _stepCount = 4;

  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _step = 0;

  late final _statementDayController = TextEditingController(text: widget.card?.statementDay.toString() ?? '');
  late final _paymentDueDayController = TextEditingController(text: widget.card?.paymentDueDay.toString() ?? '');
  late final _creditLimitController = TextEditingController(text: widget.card?.creditLimit.toStringAsFixed(2) ?? '');
  late final _sharedLimitNameController = TextEditingController();
  late final _sharedLimitAmountController = TextEditingController();

  /// Add mode, brand-new-pair case: the second physical card's own fields —
  /// used only when [_addNewPairCard] is true, mirroring the first card's
  /// identity/billing controllers one-for-one.
  final _pairLastFourDigitsController = TextEditingController();
  final _pairCardHolderNameController = TextEditingController();
  final _pairNicknameController = TextEditingController();
  final _pairStatementDayController = TextEditingController();
  final _pairPaymentDueDayController = TextEditingController();
  CardNetwork? _pairCardNetwork;

  /// Add mode: user opted to create a second brand-new card sharing this
  /// one's limit, entered together in this same form/save — the simplified
  /// replacement for the old "does an existing card share this?" question
  /// when no same-bank sibling exists yet.
  bool _addNewPairCard = false;
  late final _minimumDuePercentController = TextEditingController(
    text: widget.card?.minimumDuePercent?.toString() ?? '',
  );
  late final _lastFourDigitsController = TextEditingController(text: widget.card?.lastFourDigits ?? '')
    ..addListener(() => setState(() {}));
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
  late final _cardHolderNameController = TextEditingController(text: widget.card?.cardHolderName ?? '')
    ..addListener(() => setState(() {}));
  late final _nicknameController = TextEditingController()..addListener(() => setState(() {}));
  late final _notesController = TextEditingController();

  /// Only used in create mode when the user chooses to link an already-existing
  /// (unused) card account instead of having a new one created for them.
  String? _linkedAccountId;
  late bool _autoPay = widget.card?.autoPay ?? false;
  late CreditCardStatus _status = widget.card?.status ?? CreditCardStatus.active;
  late CardNetwork? _cardNetwork = widget.card?.cardNetwork;

  /// How this card's limit is sourced — see [_LimitSource]. Initialized once
  /// the current shared limit (if any) is known, in [initState]/[build].
  /// Only driven directly by the user in **edit** mode; in add mode, the
  /// only way to share a limit is the "Add a linked card" toggle creating
  /// both cards together (see [_addNewPairCard]) — no automatic same-bank
  /// detection/suggestion.
  _LimitSource _limitSource = _LimitSource.standalone;
  String? _selectedSharedLimitId;
  bool _sharedLimitNamePrefilled = false;

  /// The linked account's bank/color, mirrored here for editing and synced
  /// back onto the [Account] on save — a credit card IS an account, so its
  /// bank identity and color live there, not on [CreditCardProfile].
  String? _bankId;
  int _colorValue = AppColors.primary.toARGB32();
  int? _colorAppliedByBank;
  bool _isSaving = false;
  final _nicknameFocusNode = FocusNode();
  final _cardHolderNameFocusNode = FocusNode();
  final _lastFourDigitsFocusNode = FocusNode();
  final _paymentDueDayFocusNode = FocusNode();

  bool get _isEditing => widget.card != null;

  /// What the card is called everywhere — the typed nickname when present,
  /// otherwise the auto-computed "{bank} {network} • ****{last4}" name.
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
    // Prefill from the linked account so editing can change its bank/color/notes.
    final card = widget.card;
    if (card != null) {
      final account = (ref.read(accountsStreamProvider).value ?? const [])
          .where((a) => a.id == card.accountId)
          .firstOrNull;
      if (account != null) {
        _bankId = account.bankId ?? BankRegistry.matchByName(account.name)?.id;
        _colorValue = account.colorValue;
        _notesController.text = account.notes ?? '';
        // An account name that differs from the auto-computed one was a
        // user-typed nickname — surface it back into the nickname field.
        final computed = cardDisplayName(
          bank: BankRegistry.byId(_bankId),
          networkLabel: card.cardNetwork?.label,
          last4: card.lastFourDigits,
        );
        if (account.name != computed) _nicknameController.text = account.name;
      }
      final currentSharedLimit = ref.read(sharedCreditLimitForCardProvider(card.id));
      if (currentSharedLimit != null) {
        _limitSource = _LimitSource.existingSharedLimit;
        _selectedSharedLimitId = currentSharedLimit.id;
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _statementDayController.dispose();
    _paymentDueDayController.dispose();
    _creditLimitController.dispose();
    _sharedLimitNameController.dispose();
    _sharedLimitAmountController.dispose();
    _minimumDuePercentController.dispose();
    _lastFourDigitsController.dispose();
    _annualFeeController.dispose();
    _joiningFeeController.dispose();
    _interestRateController.dispose();
    _rewardNotesController.dispose();
    _autoDebitAccountController.dispose();
    _cardHolderNameController.dispose();
    _nicknameController.dispose();
    _notesController.dispose();
    _pairLastFourDigitsController.dispose();
    _pairCardHolderNameController.dispose();
    _pairNicknameController.dispose();
    _pairStatementDayController.dispose();
    _pairPaymentDueDayController.dispose();
    _nicknameFocusNode.dispose();
    _cardHolderNameFocusNode.dispose();
    _lastFourDigitsFocusNode.dispose();
    _paymentDueDayFocusNode.dispose();
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
      // A different bank changes the linked card's inherited bank too, so
      // the toggle resets rather than silently carrying over.
      _addNewPairCard = false;
      _selectedSharedLimitId = _isEditing ? _selectedSharedLimitId : null;
      // Keep the shared-limit name in step with the bank pick, as long as
      // the user hasn't typed something of their own into it yet.
      if (_limitSource == _LimitSource.newSharedLimit &&
          !_sharedLimitNamePrefilled &&
          _sharedLimitNameController.text.trim().isEmpty) {
        _sharedLimitNameController.text = bank?.name ?? '';
      }
    });
  }

  double? _parseOptionalAmount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  void _next() {
    if (_step == _stepCount - 1) {
      _save();
      return;
    }
    _goToStep(_step + 1);
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    _goToStep(_step - 1);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(creditCardRepositoryProvider);
      final minimumDuePercent = double.tryParse(_minimumDuePercentController.text.trim());
      final statementDay = int.parse(_statementDayController.text.trim());
      final paymentDueDay = int.parse(_paymentDueDayController.text.trim());

      // Resolve the shared-limit facility (if any) before touching the
      // card itself — a brand-new facility needs to exist first so the
      // card can point at its id.
      String? sharedLimitId;
      var clearSharedLimitId = false;
      if (_isEditing) {
        switch (_limitSource) {
          case _LimitSource.standalone:
            clearSharedLimitId = true;
          case _LimitSource.newSharedLimit:
            final sharedLimit = await ref.read(sharedCreditLimitRepositoryProvider).createSharedLimit(
                  name: _sharedLimitNameController.text.trim(),
                  creditLimit: double.parse(_sharedLimitAmountController.text.trim()),
                );
            sharedLimitId = sharedLimit.id;
          case _LimitSource.existingSharedLimit:
            sharedLimitId = _selectedSharedLimitId;
        }
      } else if (_addNewPairCard) {
        // Brand-new pair entered together in this same form: create the
        // facility now, the second card gets created further below once
        // this card's own account/id exist.
        final sharedLimit = await ref.read(sharedCreditLimitRepositoryProvider).createSharedLimit(
              name: BankRegistry.byId(_bankId)?.name ?? 'Shared limit',
              creditLimit: double.parse(_sharedLimitAmountController.text.trim()),
            );
        sharedLimitId = sharedLimit.id;
      }
      final hasSharedLimit = sharedLimitId != null;
      final creditLimit = hasSharedLimit ? null : double.parse(_creditLimitController.text.trim());

      final cardHolderName =
          _cardHolderNameController.text.trim().isEmpty ? null : _cardHolderNameController.text.trim();
      final lastFourDigits = _lastFourDigitsController.text.trim();
      final nickname = _nicknameController.text.trim();
      final computedName = nickname.isNotEmpty
          ? nickname
          : cardDisplayName(
              bank: BankRegistry.byId(_bankId),
              networkLabel: _cardNetwork?.label,
              last4: lastFourDigits.isEmpty ? null : lastFourDigits,
            );

      if (_isEditing) {
        // Sync the linked account's name/bank/color/notes — that's what a
        // card's display identity actually is (a card IS an account).
        final account = (ref.read(accountsStreamProvider).value ?? const [])
            .where((a) => a.id == widget.card!.accountId)
            .firstOrNull;
        if (account != null) {
          final notes = _notesController.text.trim();
          await ref.read(accountRepositoryProvider).editAccount(
                account,
                name: computedName,
                bankId: _bankId,
                clearBankId: _bankId == null,
                colorValue: _colorValue,
                notes: notes.isEmpty ? null : notes,
                clearNotes: notes.isEmpty,
              );
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
          lastFourDigits: lastFourDigits.isEmpty ? null : lastFourDigits,
          annualFee: _parseOptionalAmount(_annualFeeController.text) ?? 0,
          joiningFee: _parseOptionalAmount(_joiningFeeController.text) ?? 0,
          interestRatePercent: _parseOptionalAmount(_interestRateController.text),
          rewardNotes: _rewardNotesController.text.trim().isEmpty ? null : _rewardNotesController.text.trim(),
          autoDebitAccount: _autoPay && _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
          cardHolderName: cardHolderName,
          clearCardHolderName: cardHolderName == null,
          sharedLimitId: sharedLimitId,
          clearSharedLimitId: clearSharedLimitId,
        );
      } else {
        // Use a linked existing card account if the user picked one; otherwise
        // create the card's account inline so "add a card" is a single step.
        var accountId = _linkedAccountId;
        if (accountId == null) {
          final account = await ref.read(accountRepositoryProvider).createAccount(
                name: computedName,
                type: AccountType.card,
                openingBalance: 0,
                colorValue: _colorValue,
                bankId: _bankId,
                notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
              );
          accountId = account.id;
        }
        await repository.createCard(
          accountId: accountId,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          creditLimit: creditLimit ?? 0,
          minimumDuePercent: minimumDuePercent,
          autoPay: _autoPay,
          cardNetwork: _cardNetwork,
          lastFourDigits: lastFourDigits.isEmpty ? null : lastFourDigits,
          annualFee: _parseOptionalAmount(_annualFeeController.text) ?? 0,
          joiningFee: _parseOptionalAmount(_joiningFeeController.text) ?? 0,
          interestRatePercent: _parseOptionalAmount(_interestRateController.text),
          rewardNotes: _rewardNotesController.text.trim().isEmpty ? null : _rewardNotesController.text.trim(),
          autoDebitAccount: _autoPay && _autoDebitAccountController.text.trim().isNotEmpty
              ? _autoDebitAccountController.text.trim()
              : null,
          cardHolderName: cardHolderName,
          sharedLimitId: sharedLimitId,
        );

        if (_addNewPairCard && sharedLimitId != null) {
          final pairLastFourDigits = _pairLastFourDigitsController.text.trim();
          final pairNickname = _pairNicknameController.text.trim();
          final pairCardHolderName = _pairCardHolderNameController.text.trim();
          final pairAccount = await ref.read(accountRepositoryProvider).createAccount(
                name: pairNickname.isNotEmpty
                    ? pairNickname
                    : cardDisplayName(
                        bank: BankRegistry.byId(_bankId),
                        networkLabel: _pairCardNetwork?.label,
                        last4: pairLastFourDigits.isEmpty ? null : pairLastFourDigits,
                      ),
                type: AccountType.card,
                openingBalance: 0,
                colorValue: _colorValue,
                bankId: _bankId,
              );
          await repository.createCard(
            accountId: pairAccount.id,
            statementDay: int.parse(_pairStatementDayController.text.trim()),
            paymentDueDay: int.parse(_pairPaymentDueDayController.text.trim()),
            creditLimit: 0,
            cardNetwork: _pairCardNetwork,
            lastFourDigits: pairLastFourDigits.isEmpty ? null : pairLastFourDigits,
            cardHolderName: pairCardHolderName.isEmpty ? null : pairCardHolderName,
            sharedLimitId: sharedLimitId,
          );
        }
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

  Widget _ownLimitField() {
    return _PremiumField(
      controller: _creditLimitController,
      label: 'Credit limit',
      helperText: 'Your total spending limit on this card',
      prefixIcon: Icons.currency_rupee_rounded,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: Validators.amount,
    );
  }

  Widget _sharedAmountField() {
    return _PremiumField(
      controller: _sharedLimitAmountController,
      label: 'Total credit limit',
      helperText: 'One combined limit shared across the linked cards',
      prefixIcon: Icons.currency_rupee_rounded,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: Validators.amount,
    );
  }

  /// Add mode: the plain-language limit flow. Always the normal own-limit
  /// field, plus a toggle to enter a second brand-new card alongside it,
  /// sharing one limit between the two — both get created together on
  /// save. No automatic same-bank detection/suggestion here: linking an
  /// *existing* card to a shared limit is a manual, per-card choice made
  /// in that card's own edit screen, not something this form auto-detects
  /// or suggests while adding a different card.
  List<Widget> _addModeLimitFields(BuildContext context) {
    return [
      _ownLimitField(),
      const SizedBox(height: AppSizes.md),
      _pairLimitToggleCard(context),
      if (_addNewPairCard) ...[
        const SizedBox(height: AppSizes.md),
        _sharedAmountField(),
        const SizedBox(height: AppSizes.md),
        _secondCardFields(context),
      ],
    ];
  }

  /// The entry point into the brand-new-pair flow — a tappable premium card
  /// (gradient icon badge, title/subtitle, trailing switch) rather than a
  /// plain [SwitchListTile], matching the shared-limit hero card's styling
  /// on the list screen so this reads as the same feature, not a buried
  /// checkbox.
  Widget _pairLimitToggleCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: _addNewPairCard ? colors.primaryContainer.withValues(alpha: 0.35) : colors.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _addNewPairCard = !_addNewPairCard;
          if (_addNewPairCard && _sharedLimitAmountController.text.trim().isEmpty) {
            _sharedLimitAmountController.text = _creditLimitController.text.trim();
          }
        }),
        child: Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: _addNewPairCard ? colors.primary.withValues(alpha: 0.4) : colors.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: AppColors.primaryGradient),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: const Icon(Icons.style_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add a linked card', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      'One shared limit for two cards — each keeps its own number and bill',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _addNewPairCard,
                onChanged: (value) => setState(() {
                  _addNewPairCard = value;
                  if (value && _sharedLimitAmountController.text.trim().isEmpty) {
                    _sharedLimitAmountController.text = _creditLimitController.text.trim();
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add mode, brand-new-pair case: the linked card's own compact set of
  /// fields — bank is inherited from the first card (a shared limit is
  /// always same-bank), so only identity + billing-cycle fields are asked.
  Widget _secondCardFields(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card_rounded, size: AppSizes.iconSm, color: context.colors.primary),
              const SizedBox(width: AppSizes.xs),
              Text('Your linked card', style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          _PremiumField(controller: _pairNicknameController, label: 'Card name (optional)'),
          const SizedBox(height: AppSizes.sm),
          _PremiumDropdown<CardNetwork?>(
            value: _pairCardNetwork,
            label: 'Card network (optional)',
            items: [
              const DropdownMenuItem<CardNetwork?>(value: null, child: Text('Not set')),
              for (final network in CardNetwork.values) DropdownMenuItem(value: network, child: Text(network.label)),
            ],
            onChanged: (value) => setState(() => _pairCardNetwork = value),
          ),
          const SizedBox(height: AppSizes.sm),
          _PremiumField(
            controller: _pairLastFourDigitsController,
            label: 'Last 4 digits (optional)',
            prefixText: '•••• ',
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),
          const SizedBox(height: AppSizes.sm),
          _PremiumField(
            controller: _pairStatementDayController,
            label: 'Bill generated on',
            suffixText: 'day of month',
            keyboardType: TextInputType.number,
            validator: (v) => _addNewPairCard ? _dayValidator(v) : null,
          ),
          const SizedBox(height: AppSizes.sm),
          _PremiumField(
            controller: _pairPaymentDueDayController,
            label: 'Payment due on',
            suffixText: 'day of next month',
            keyboardType: TextInputType.number,
            validator: (v) => _addNewPairCard ? _dayValidator(v) : null,
          ),
        ],
      ),
    );
  }

  /// Step 1 — bank, identity, network & number. Kept as one step (rather
  /// than split further) since the reference design's "Card basics" groups
  /// exactly these fields together.
  Widget _buildBasicsStep(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final existingCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final linkedAccountIds = existingCards.where((c) => c.id != widget.card?.id).map((c) => c.accountId).toSet();
    // Card-type accounts that aren't already tied to a card — only offered as
    // an optional shortcut, never as a required (and possibly empty) dropdown.
    final unusedCardAccounts =
        accounts.where((a) => a.type == AccountType.card && !linkedAccountIds.contains(a.id)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _StepHeader(
          step: 1,
          title: 'Card basics',
          subtitle: 'The bank, name, and network for this card.',
        ),
        const SizedBox(height: AppSizes.lg),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            boxShadow: AppShadows.soft(context),
          ),
          child: CreditCardVisual(
            title: _displayTitle,
            colorValue: _colorValue,
            bankId: _bankId,
            cardNetwork: _cardNetwork,
            lastFourDigits:
                _lastFourDigitsController.text.trim().isEmpty ? null : _lastFourDigitsController.text.trim(),
            cardHolderName:
                _cardHolderNameController.text.trim().isEmpty ? null : _cardHolderNameController.text.trim(),
          ),
        ),
        const SizedBox(height: AppSizes.xl),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isEditing && unusedCardAccounts.isNotEmpty) ...[
                _PremiumDropdown<String?>(
                  value: _linkedAccountId,
                  label: 'Or link an existing card account (optional)',
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Create a new card')),
                    for (final account in unusedCardAccounts)
                      DropdownMenuItem<String?>(value: account.id, child: Text(account.name)),
                  ],
                  onChanged: (value) => setState(() => _linkedAccountId = value),
                ),
                const SizedBox(height: AppSizes.md),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                onTap: _pickBank,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Row(
                    children: [
                      BankAvatar(bankId: _bankId, size: 30),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Bank',
                              style: context.textTheme.labelSmall
                                  ?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.55)),
                            ),
                            Text(
                              BankRegistry.byId(_bankId)?.name ?? 'Select bank (optional)',
                              style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: context.colors.onSurface.withValues(alpha: 0.4)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSizes.xs, left: AppSizes.xs),
                child: Text(
                  'Shown as "$_displayTitle"',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: AppSizes.md),
              _PremiumField(
                controller: _nicknameController,
                focusNode: _nicknameFocusNode,
                label: 'Card name (optional)',
                helperText: 'A nickname like "Travel card" — otherwise named after the bank',
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _cardHolderNameFocusNode.requestFocus(),
              ),
              const SizedBox(height: AppSizes.md),
              _PremiumField(
                controller: _cardHolderNameController,
                focusNode: _cardHolderNameFocusNode,
                label: 'Card holder name (optional)',
                helperText: 'Name printed on the card, e.g. ABIN JOHN',
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _lastFourDigitsFocusNode.requestFocus(),
              ),
              if (_isEditing) ...[
                const SizedBox(height: AppSizes.md),
                _PremiumDropdown<CreditCardStatus>(
                  value: _status,
                  label: 'Card status',
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
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Card network',
                style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSizes.sm),
              Wrap(
                spacing: AppSizes.sm,
                runSpacing: AppSizes.sm,
                children: [
                  for (final network in CardNetwork.values)
                    _NetworkChip(
                      network: network,
                      selected: _cardNetwork == network,
                      onTap: () => setState(() => _cardNetwork = _cardNetwork == network ? null : network),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              _PremiumField(
                controller: _lastFourDigitsController,
                focusNode: _lastFourDigitsFocusNode,
                label: 'Last 4 digits (optional)',
                prefixText: '•••• ',
                keyboardType: TextInputType.number,
                maxLength: 4,
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }

  /// Step 2 — credit limit setup. Reuses the exact add/edit-mode logic and
  /// widgets from the original single-scroll form untouched.
  Widget _buildLimitStep(BuildContext context) {
    final allSharedLimits = ref.watch(sharedCreditLimitsStreamProvider).value ?? const [];
    // In edit mode, offer every facility except the one already selected
    // (switching "into itself" is a no-op the picker shouldn't list).
    final selectableSharedLimits =
        allSharedLimits.where((g) => g.id != (_isEditing ? _selectedSharedLimitId : null)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _StepHeader(
          step: 2,
          title: 'Credit limit',
          subtitle: 'How would you like to set up the credit limit?',
        ),
        const SizedBox(height: AppSizes.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isEditing) ...[
                Text(
                  'Does this card have its own limit, or does it share one credit limit with '
                  'another card from the same bank? Its own bill, due date, and transactions '
                  'stay separate either way.',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: AppSizes.md),
                SegmentedButton<_LimitSource>(
                  segments: const [
                    ButtonSegment(value: _LimitSource.standalone, label: Text('Own limit')),
                    ButtonSegment(value: _LimitSource.newSharedLimit, label: Text('New shared')),
                    ButtonSegment(value: _LimitSource.existingSharedLimit, label: Text('Shared')),
                  ],
                  selected: {_limitSource},
                  onSelectionChanged: (selection) => setState(() {
                    _limitSource = selection.first;
                    if (_limitSource == _LimitSource.newSharedLimit &&
                        _sharedLimitNameController.text.trim().isEmpty) {
                      _sharedLimitNameController.text = BankRegistry.byId(_bankId)?.name ?? '';
                      _sharedLimitNamePrefilled = true;
                    }
                  }),
                ),
                const SizedBox(height: AppSizes.md),
                switch (_limitSource) {
                  _LimitSource.standalone => _ownLimitField(),
                  _LimitSource.newSharedLimit => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PremiumField(
                          controller: _sharedLimitNameController,
                          onChanged: (_) => _sharedLimitNamePrefilled = false,
                          label: 'Shared limit name',
                          helperText: 'Usually just the bank name, e.g. "SBI"',
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
                        ),
                        const SizedBox(height: AppSizes.md),
                        _sharedAmountField(),
                      ],
                    ),
                  _LimitSource.existingSharedLimit => selectableSharedLimits.isEmpty
                      ? Text(
                          'No shared credit limits exist yet. Choose "New shared" instead.',
                          style: context.textTheme.bodySmall?.copyWith(color: context.colors.error),
                        )
                      : _PremiumDropdown<String>(
                          value: _selectedSharedLimitId,
                          label: 'Shared credit limit',
                          items: [
                            for (final sharedLimit in selectableSharedLimits)
                              DropdownMenuItem(
                                value: sharedLimit.id,
                                child: Text(
                                  '${sharedLimit.name} — ${sharedLimit.creditLimit.toStringAsFixed(2)}',
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(() => _selectedSharedLimitId = value),
                          validator: (value) => value == null ? 'Choose a shared credit limit' : null,
                        ),
                },
              ] else
                ..._addModeLimitFields(context),
            ],
          ),
        ),
        ],
      ),
    );
  }

  /// Step 3 — billing dates plus fees/rewards/autopay, matching the
  /// reference design's "Card details" step.
  Widget _buildDetailsStep(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _StepHeader(
          step: 3,
          title: 'Card details',
          subtitle: 'These details are specific to this card.',
        ),
        const SizedBox(height: AppSizes.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PremiumField(
                controller: _statementDayController,
                label: 'Bill generated on',
                helperText: 'The day each month your card bill is generated (e.g. 17)',
                suffixText: 'day of month',
                keyboardType: TextInputType.number,
                validator: _dayValidator,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _paymentDueDayFocusNode.requestFocus(),
              ),
              const SizedBox(height: AppSizes.md),
              _PremiumField(
                controller: _paymentDueDayController,
                focusNode: _paymentDueDayFocusNode,
                label: 'Payment due on',
                helperText: 'The day next month you pay it (e.g. 5)',
                suffixText: 'day of next month',
                keyboardType: TextInputType.number,
                validator: _dayValidator,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fees & extras', style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Optional — annual fee, minimum due, rewards, and auto pay.',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: AppSizes.md),
              _PremiumField(
                controller: _minimumDuePercentController,
                label: 'Minimum payment %',
                helperText: 'The smallest part of your bill you must pay to avoid a late fee. Leave blank if unsure.',
                suffixText: '%',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSizes.sm),
              _PremiumField(
                controller: _annualFeeController,
                label: 'Annual fee (optional)',
                prefixIcon: Icons.local_offer_outlined,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSizes.sm),
              _PremiumField(
                controller: _joiningFeeController,
                label: 'Joining fee (optional)',
                prefixIcon: Icons.card_giftcard_outlined,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSizes.sm),
              _PremiumField(
                controller: _interestRateController,
                label: 'Interest rate (%)',
                helperText: 'For your reference only — not used in any calculation.',
                suffixText: '%',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSizes.sm),
              _PremiumField(controller: _rewardNotesController, label: 'Reward / cashback notes (optional)'),
              const SizedBox(height: AppSizes.sm),
              _PremiumField(controller: _notesController, label: 'Notes (optional)'),
              const SizedBox(height: AppSizes.md),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto pay'),
                  subtitle: const Text('For your reference only — this app does not make payments automatically.'),
                  value: _autoPay,
                  onChanged: (value) => setState(() => _autoPay = value),
                ),
              ),
              if (_autoPay)
                Padding(
                  padding: const EdgeInsets.only(top: AppSizes.sm),
                  child: _PremiumField(controller: _autoDebitAccountController, label: 'Auto debit account'),
                ),
            ],
          ),
        ),
        ],
      ),
    );
  }

  /// Step 4 — personalize the card's color and review the live preview
  /// before saving, matching the reference design's "Customize card" step.
  Widget _buildCustomizeStep(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _StepHeader(
          step: 4,
          title: 'Customize card',
          subtitle: 'Personalize your card for easy identification.',
        ),
        const SizedBox(height: AppSizes.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Card color', style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSizes.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final color in _cardThemeColors)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSizes.sm),
                        child: GestureDetector(
                          onTap: () => setState(() => _colorValue = color.toARGB32()),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, Color.lerp(color, Colors.black, 0.4)!],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: _colorValue == color.toARGB32()
                                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1)]
                                  : null,
                              border: _colorValue == color.toARGB32()
                                  ? Border.all(color: context.colors.surface, width: 2)
                                  : null,
                            ),
                            child: _colorValue == color.toARGB32()
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
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
              const SizedBox(height: AppSizes.xl),
              Row(
                children: [
                  Icon(Icons.visibility_outlined, size: AppSizes.iconSm, color: context.colors.primary),
                  const SizedBox(width: AppSizes.xs),
                  Text('Live preview', style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  boxShadow: AppShadows.soft(context),
                ),
                child: CreditCardVisual(
                  title: _displayTitle,
                  colorValue: _colorValue,
                  bankId: _bankId,
                  cardNetwork: _cardNetwork,
                  lastFourDigits:
                      _lastFourDigitsController.text.trim().isEmpty ? null : _lastFourDigitsController.text.trim(),
                  cardHolderName:
                      _cardHolderNameController.text.trim().isEmpty ? null : _cardHolderNameController.text.trim(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: AppSizes.xs),
            Text(
              'Your data is 100% secure',
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
          title: Text(_isEditing ? 'Card Settings' : 'Add Credit Card'),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.sm, AppSizes.lg, AppSizes.md),
                  child: _StepProgressBar(currentStep: _step, stepCount: _stepCount),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) => setState(() => _step = page),
                    children: [
                      _buildBasicsStep(context),
                      _buildLimitStep(context),
                      _buildDetailsStep(context),
                      _buildCustomizeStep(context),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.lg),
                  child: PrimaryButton(
                    label: _step == _stepCount - 1 ? (_isEditing ? 'Save changes' : 'Add card') : 'Continue',
                    isLoading: _isSaving,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
