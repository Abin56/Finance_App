import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';

/// Bottom sheet for creating or editing a person. Opening balance can
/// only be set on creation — editing it later would silently rewrite the
/// running-balance timeline's starting point, same rationale as
/// `AccountFormSheet`'s locked opening balance field.
class PersonFormSheet extends ConsumerStatefulWidget {
  const PersonFormSheet({super.key, this.person});

  final Person? person;

  static Future<void> show(BuildContext context, {Person? person}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
  late final _emailController = TextEditingController(text: widget.person?.email);
  late final _notesController = TextEditingController(text: widget.person?.notes ?? '');
  late final _openingBalanceController = TextEditingController(
    text: widget.person == null ? '0' : widget.person!.openingBalance.toStringAsFixed(2),
  );
  late int _avatarColorValue = widget.person?.avatarColorValue ?? AppColors.categoryPalette.first.toARGB32();
  bool _isSaving = false;

  bool get _isEditing => widget.person != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(personRepositoryProvider);
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();

      if (_isEditing) {
        await repository.editPerson(
          widget.person!,
          name: _nameController.text.trim(),
          phone: phone.isEmpty ? null : phone,
          email: email.isEmpty ? null : email,
          notes: _notesController.text.trim(),
          avatarColorValue: _avatarColorValue,
        );
      } else {
        await repository.createPerson(
          name: _nameController.text.trim(),
          phone: phone.isEmpty ? null : phone,
          email: email.isEmpty ? null : email,
          notes: _notesController.text.trim(),
          avatarColorValue: _avatarColorValue,
          openingBalance: double.parse(_openingBalanceController.text.trim()),
        );
      }
      if (mounted) Navigator.of(context).pop();
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
                _isEditing ? 'Edit person' : 'Add person',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: Validators.required,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                keyboardType: TextInputType.phone,
                validator: Validators.phone,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _openingBalanceController,
                enabled: !_isEditing,
                decoration: InputDecoration(
                  labelText: 'Starting Amount Left',
                  helperText: _isEditing
                      ? 'Starting Amount Left can\'t be changed later'
                      : 'Positive = they owe you, negative = you owe them',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: Validators.signedAmount,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.md),
              Wrap(
                spacing: AppSizes.sm,
                children: [
                  for (final color in AppColors.categoryPalette)
                    GestureDetector(
                      onTap: () => setState(() => _avatarColorValue = color.toARGB32()),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: color,
                        child: _avatarColorValue == color.toARGB32()
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add person',
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
