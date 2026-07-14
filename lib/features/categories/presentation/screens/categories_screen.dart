import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../data/category_repository.dart';
import '../../domain/category.dart';
import '../../domain/category_type.dart';
import '../providers/category_providers.dart';
import '../widgets/category_form_sheet.dart';
import '../widgets/category_tile.dart';
import 'categories_trash_screen.dart';

/// Manage categories — split into Expense / Income tabs since a flat list
/// mixing both is hard to scan. "Both"-type categories appear on both tabs.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(categoryRepositoryProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Expense'), Tab(text: 'Income')],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoriesTrashScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'categories_fab',
        onPressed: () => CategoryFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (categories) {
          if (categories.isEmpty) {
            return EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              subtitle: 'Add a category to start organizing your transactions.',
              action: FilledButton(
                onPressed: () => CategoryFormSheet.show(context),
                child: const Text('Add your first category'),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _CategoryList(
                categories: categories.where((c) => c.type.appliesTo(TransactionType.expense)).toList(),
                repository: repository,
              ),
              _CategoryList(
                categories: categories.where((c) => c.type.appliesTo(TransactionType.income)).toList(),
                repository: repository,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categories, required this.repository});

  final List<Category> categories;
  final CategoryRepository repository;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const EmptyState(
        icon: Icons.category_outlined,
        title: 'Nothing here yet',
        subtitle: 'Categories for this type will appear here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.sm),
            child: Dismissible(
              key: ValueKey(category.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
              ),
              onDismissed: (_) async {
                await repository.softDelete(category);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${category.name} moved to trash'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => repository.restore(category),
                    ),
                  ),
                );
              },
              child: CategoryTile(
                category: category,
                onTap: () => CategoryFormSheet.show(context, category: category),
              ),
            ),
          ),
      ],
    );
  }
}
