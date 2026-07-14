import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import 'category_type.dart';

/// One row of seed data for [DefaultCategories.all] — turned into a real
/// [Category] document by `CategoryRepository.seedDefaultsIfEmpty`.
class DefaultCategorySeed {
  const DefaultCategorySeed({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.color,
  });

  final String name;
  final CategoryType type;
  final String iconKey;
  final Color color;
}

/// The starter category set seeded into every new user's `categories`
/// collection the first time it's read and found empty.
abstract class DefaultCategories {
  DefaultCategories._();

  static final List<DefaultCategorySeed> all = [
    DefaultCategorySeed(
      name: 'Salary',
      type: CategoryType.income,
      iconKey: 'work',
      color: AppColors.categoryPalette[5],
    ),
    DefaultCategorySeed(
      name: 'Freelance',
      type: CategoryType.income,
      iconKey: 'laptop',
      color: AppColors.categoryPalette[8],
    ),
    DefaultCategorySeed(
      name: 'Food',
      type: CategoryType.expense,
      iconKey: 'restaurant',
      color: AppColors.categoryPalette[2],
    ),
    DefaultCategorySeed(
      name: 'Transport',
      type: CategoryType.expense,
      iconKey: 'car',
      color: AppColors.categoryPalette[4],
    ),
    DefaultCategorySeed(
      name: 'Shopping',
      type: CategoryType.expense,
      iconKey: 'shopping_bag',
      color: AppColors.categoryPalette[6],
    ),
    DefaultCategorySeed(
      name: 'Bills & Utilities',
      type: CategoryType.expense,
      iconKey: 'receipt',
      color: AppColors.categoryPalette[3],
    ),
    DefaultCategorySeed(
      name: 'Entertainment',
      type: CategoryType.expense,
      iconKey: 'movie',
      color: AppColors.categoryPalette[7],
    ),
    DefaultCategorySeed(
      name: 'Health',
      type: CategoryType.expense,
      iconKey: 'health',
      color: AppColors.categoryPalette[1],
    ),
    DefaultCategorySeed(
      name: 'Transfer',
      type: CategoryType.both,
      iconKey: 'transfer',
      color: AppColors.categoryPalette[9],
    ),
    DefaultCategorySeed(
      name: 'Other',
      type: CategoryType.both,
      iconKey: 'other',
      color: AppColors.categoryPalette[0],
    ),
  ];
}
