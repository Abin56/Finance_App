import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/person.dart';
import '../providers/people_providers.dart';
import 'person_avatar.dart';
import 'person_form_sheet.dart';

/// Searchable single-select person picker — a standalone bottom sheet for
/// screens that just need "pick one existing person, or add a new one and
/// pick that instead," without the split-specific dropdown-per-row logic
/// [SplitExpenseFormSheet]'s `_ParticipantField` carries. Resolves to the
/// chosen [Person], or null if dismissed without a selection.
Future<Person?> showPersonPickerSheet(BuildContext context) {
  return showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PersonPickerSheet(),
  );
}

class _PersonPickerSheet extends ConsumerStatefulWidget {
  const _PersonPickerSheet();

  @override
  ConsumerState<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<_PersonPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createNewPerson() async {
    await PersonFormSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleStreamProvider);
    final people = peopleAsync.value ?? const [];
    final filtered = _query.isEmpty
        ? people
        : people.where((p) => p.name.toLowerCase().contains(_query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (sheetContext, scrollController) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSizes.sm),
              Text('Select a person', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.sm),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search people',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: AppSizes.iconSm),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: AppSizes.iconSm),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSizes.xs),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('Add new person'),
                      onTap: _createNewPerson,
                    ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
                        child: Center(
                          child: Text(
                            'No people match "$_query"',
                            style: context.textTheme.bodyMedium
                                ?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                          ),
                        ),
                      )
                    else
                      for (final person in filtered)
                        ListTile(
                          leading: PersonAvatar(name: person.name, colorValue: person.avatarColorValue),
                          title: Text(person.name),
                          onTap: () => Navigator.of(context).pop(person),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
