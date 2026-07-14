import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/category.dart';
import '../../domain/category_icons.dart';
import '../../domain/category_type.dart';
import '../providers/category_providers.dart';

/// Bottom sheet for creating or editing a category.
class CategoryFormSheet extends ConsumerStatefulWidget {
  const CategoryFormSheet({super.key, this.category});

  final Category? category;

  static Future<void> show(BuildContext context, {Category? category}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryFormSheet(category: category),
    );
  }

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.category?.name);
  late CategoryType _type = widget.category?.type ?? CategoryType.expense;
  late String _iconKey = widget.category?.iconKey ?? CategoryIcons.catalog.keys.first;
  late int _colorValue = widget.category?.colorValue ?? AppColors.categoryPalette.first.toARGB32();
  late bool _isActive = widget.category?.isActive ?? true;
  bool _isSaving = false;

  bool get _isEditing => widget.category != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repository = ref.read(categoryRepositoryProvider);
      if (_isEditing) {
        await repository.editCategory(
          widget.category!,
          name: _nameController.text.trim(),
          type: _type,
          iconKey: _iconKey,
          colorValue: _colorValue,
          isActive: _isActive,
        );
      } else {
        await repository.createCategory(
          name: _nameController.text.trim(),
          type: _type,
          iconKey: _iconKey,
          colorValue: _colorValue,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save category: $e')),
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
                _isEditing ? 'Edit category' : 'Add category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSizes.lg),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Category name'),
                validator: Validators.required,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSizes.md),
              DropdownButtonFormField<CategoryType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Applies to'),
                items: [
                  for (final type in CategoryType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: AppSizes.md),
              Text('Icon', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSizes.sm),
              Wrap(
                spacing: AppSizes.sm,
                runSpacing: AppSizes.sm,
                children: [
                  for (final entry in CategoryIcons.catalog.entries)
                    GestureDetector(
                      onTap: () => setState(() => _iconKey = entry.key),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: entry.key == _iconKey
                              ? Color(_colorValue).withValues(alpha: 0.2)
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                          border: entry.key == _iconKey
                              ? Border.all(color: Color(_colorValue), width: 2)
                              : null,
                        ),
                        child: Icon(entry.value, size: AppSizes.iconSm),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              Text('Color', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSizes.sm),
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
              if (_isEditing) ...[
                const SizedBox(height: AppSizes.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Inactive categories are hidden from new transactions'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ],
              const SizedBox(height: AppSizes.xl),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add category',
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
