import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';
import '../widgets/overall_balance_card.dart';
import '../widgets/people_filter_chips.dart';
import '../widgets/people_sort.dart';
import '../widgets/person_form_sheet.dart';
import '../widgets/person_tile.dart';
import 'people_trash_screen.dart';

/// Full people list — every person regardless of creditor/debtor status,
/// with search and the primary "add person" entry point. One of the bottom
/// nav tabs; /creditors and /debtors are filtered views over the same data.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  PeopleFilter _filter = PeopleFilter.all;
  PeopleSort _sort = PeopleSort.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Person> _applyFilters(List<Person> people) {
    final query = _query.trim().toLowerCase();
    final filtered = people.where(_filter.matches).where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          (p.phone?.toLowerCase().contains(query) ?? false) ||
          (p.email?.toLowerCase().contains(query) ?? false);
    }).toList();
    return applyPeopleSort(filtered, _sort);
  }

  Future<void> _openSortMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<PeopleSort>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in PeopleSort.values)
              ListTile(
                title: Text(sort.label),
                trailing: sort == _sort ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(sheetContext).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(personRepositoryProvider);
    final peopleAsync = ref.watch(peopleStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search people…', border: InputBorder.none),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('People'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PeopleTrashScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'people_fab',
        onPressed: () => PersonFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: peopleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (people) {
          if (people.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No people yet',
              subtitle: 'Add someone to start tracking money given, borrowed, or repaid.',
              action: FilledButton(
                onPressed: () => PersonFormSheet.show(context),
                child: const Text('Add your first person'),
              ),
            );
          }

          final visible = _applyFilters(people);
          final netBalance = people.fold(0.0, (total, p) => total + p.currentBalance);

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              OverallBalanceCard(netBalance: netBalance),
              const SizedBox(height: AppSizes.lg),
              PeopleFilterChips(selected: _filter, onChanged: (filter) => setState(() => _filter = filter)),
              const SizedBox(height: AppSizes.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('People (${visible.length})', style: Theme.of(context).textTheme.titleMedium),
                  InkWell(
                    onTap: () => _openSortMenu(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Sort: ${_sort.label}', style: Theme.of(context).textTheme.bodyMedium),
                        const Icon(Icons.expand_more_rounded, size: AppSizes.iconSm),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.xl),
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching people',
                    subtitle: 'Try a different search term or filter.',
                  ),
                ),
              for (final person in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: Dismissible(
                    key: ValueKey(person.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => confirmDelete(context, entityName: 'Person'),
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
                      await repository.softDelete(person);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${person.name} moved to trash'),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () => repository.restore(person),
                          ),
                        ),
                      );
                    },
                    child: PersonTile(
                      person: person,
                      onTap: () => context.push('${AppRoutes.people}/${person.id}'),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => PersonFormSheet.show(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add New Person'),
              ),
            ],
          );
        },
      ),
    );
  }
}
