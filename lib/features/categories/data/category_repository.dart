import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/category.dart';
import '../domain/category_type.dart';
import '../domain/default_categories.dart';

/// Category-specific persistence on top of the generic CRUD/soft-delete
/// repository, plus first-launch seeding of the default category set.
class CategoryRepository extends FirestoreCrudRepository<Category> {
  CategoryRepository(super.collection);

  Future<Category> createCategory({
    required String name,
    required CategoryType type,
    required String iconKey,
    required int colorValue,
  }) async {
    final category = Category(
      id: IdGenerator.generate(),
      name: name,
      type: type,
      iconKey: iconKey,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    await add(category.id, category);
    return category;
  }

  Future<void> editCategory(
    Category category, {
    String? name,
    CategoryType? type,
    String? iconKey,
    int? colorValue,
    bool? isActive,
  }) async {
    category.updateField(
      field: 'name',
      oldValue: category.name,
      newValue: name,
      apply: (v) => category.name = v,
    );
    category.updateField(
      field: 'type',
      oldValue: category.type,
      newValue: type,
      apply: (v) => category.type = v,
    );
    category.updateField(
      field: 'icon',
      oldValue: category.iconKey,
      newValue: iconKey,
      apply: (v) => category.iconKey = v,
    );
    category.updateField(
      field: 'color',
      oldValue: category.colorValue,
      newValue: colorValue,
      apply: (v) => category.colorValue = v,
    );
    category.updateField(
      field: 'isActive',
      oldValue: category.isActive,
      newValue: isActive,
      apply: (v) => category.isActive = v,
    );
    await update(category);
  }

  /// Populates the default category set the first time this user's
  /// `categories` collection is found empty (fresh account, or every
  /// category having since been purged). Safe to call on every cold read —
  /// it only writes when [getAll] comes back empty.
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await getAll();
    if (existing.isNotEmpty) return;

    for (final seed in DefaultCategories.all) {
      final category = Category(
        id: IdGenerator.generate(),
        name: seed.name,
        type: seed.type,
        iconKey: seed.iconKey,
        colorValue: seed.color.toARGB32(),
        createdAt: DateTime.now(),
        isDefault: true,
      );
      await add(category.id, category);
    }
  }
}
