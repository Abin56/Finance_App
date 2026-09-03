// Standard category fixture used by the benchmark run — mirrors the
// category list already used by
// test/features/sms_inbox/financial_event/sms_corpus_evaluation_test.dart's
// category-variation test group, so `categoryNameEquals` expectations in the
// shared corpus resolve against the same names.
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';

Category _category(String id, String name) => Category(
  id: id,
  name: name,
  type: CategoryType.expense,
  iconKey: 'category',
  colorValue: 0xFF000000,
  createdAt: DateTime(2026, 1, 1),
);

final List<Category> benchmarkCategories = [
  _category('cat-food-dining', 'Food & Dining'),
  _category('cat-groceries', 'Groceries'),
  _category('cat-shopping', 'Shopping'),
  _category('cat-transport', 'Transport'),
  _category('cat-fuel', 'Fuel'),
  _category('cat-entertainment', 'Entertainment'),
  _category('cat-subscriptions', 'Subscriptions'),
  _category('cat-bills-utilities', 'Bills & Utilities'),
  _category('cat-health', 'Health'),
  _category('cat-salary', 'Salary'),
  _category('cat-other', 'Other'),
];
