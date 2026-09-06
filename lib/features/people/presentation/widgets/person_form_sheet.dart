import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/inputs/color_swatch_picker.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';

/// Bottom sheet for creating or editing a person. Opening balance can
/// only be set on creation — editing it later would silently rewrite the
/// running-balance timeline's starting point, same rationale as
/// `AccountFormSheet`'s locked opening balance field.
class PersonFormSheet extends ConsumerStatefulWidget {
  const PersonFormSheet({super.key, this.person});

  final Person? person;

  /// Resolves with the created/edited person's id once saved (null if the
  /// sheet is dismissed without saving) — lets a caller like [LoanFormSheet]
  /// auto-select a person just created from a "+ Add new person" shortcut.
  static Future<String?> show(BuildContext context, {Person? person}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => PersonFormSheet(person: person),
    );
  }

  @override
  ConsumerState<PersonFormSheet> createState() => _PersonFormSheetState();
}

class _PersonFormSheetState extends ConsumerState<PersonFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.person?.name);
  late final _phoneController = TextEditingController(text: widget.person?.phone);
  late final _openingBalanceController = TextEditingController(
    text: widget.person == null ? '0' : widget.person!.openingBalance.toStringAsFixed(2),
  );
  late int _avatarColorValue = widget.person?.avatarColorValue ?? AppColors.categoryPalette.first.toARGB32();
  final _phoneFocusNode = FocusNode();
  bool _isSaving = false;

  bool get _isEditing => widget.person != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(personRepositoryProvider);
      final phone = _phoneController.text.trim();

      String personId;
      if (_isEditing) {
        await repository.editPerson(
          widget.person!,
          name: _nameController.text.trim(),
          phone: phone.isEmpty ? null : phone,
          avatarColorValue: _avatarColorValue,
        );
        personId = widget.person!.id;
      } else {
        final created = await repository.createPerson(
          name: _nameController.text.trim(),
          phone: phone.isEmpty ? null : phone,
          avatarColorValue: _avatarColorValue,
          openingBalance: double.parse(_openingBalanceController.text.trim()),
        );
        personId = created.id;
      }
      if (mounted) Navigator.of(context).pop(personId);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save person: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _isEditing ? 'Edit person' : 'Add person',
        confirmLabel: _isEditing ? 'Save changes' : 'Add person',
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Person Details'),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _nameController,
              decoration: _premiumDecoration(context, label: 'Name'),
              style: Theme.of(context).textTheme.bodyMedium,
              validator: Validators.required,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _phoneFocusNode.requestFocus(),
            ),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              decoration: _premiumDecoration(context, label: 'Phone (optional)'),
              style: Theme.of(context).textTheme.bodyMedium,
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSizes.md),
            const SectionLabel('Starting Balance'),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              controller: _openingBalanceController,
              enabled: !_isEditing,
              decoration: _premiumDecoration(
                context,
                label: 'Starting Amount Left',
                helperText: _isEditing
                    ? 'Starting Amount Left can\'t be changed later'
                    : 'Positive = they owe you, negative = you owe them',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: Validators.signedAmount,
            ),
            const SizedBox(height: AppSizes.md),
            const SectionLabel('Color'),
            const SizedBox(height: AppSizes.sm),
            ColorSwatchPicker(
              value: Color(_avatarColorValue),
              onChanged: (color) => setState(() => _avatarColorValue = color.toARGB32()),
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
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    helperText: helperText,
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
