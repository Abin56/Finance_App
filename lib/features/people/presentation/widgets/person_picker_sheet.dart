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
        : people
              .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    final hasPeople = people.isNotEmpty;

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
              Text(
                'Select a person',
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Choose who this expense is shared with',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search people...',
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: AppSizes.iconSm,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: AppSizes.iconSm,
                          ),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSizes.md),
              _AddPersonRow(onTap: _createNewPerson),
              const SizedBox(height: AppSizes.sm),
              if (hasPeople) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.xs,
                    vertical: AppSizes.xs,
                  ),
                  child: Text(
                    'PEOPLE',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.5),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: !hasPeople
                    ? const _EmptyState(
                        title: 'No people yet',
                        message: 'Add someone to start sharing expenses.',
                      )
                    : filtered.isEmpty
                    ? const _EmptyState(
                        title: 'No people found',
                        message: 'Try a different name.',
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: AppSizes.lg),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSizes.xs),
                        itemBuilder: (context, index) {
                          final person = filtered[index];
                          return _PersonRow(
                            person: person,
                            onTap: () => Navigator.of(context).pop(person),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Add new person" action row — visually distinct from the people list
/// below it (icon in a lime-tinted circle, chevron affordance) so it reads
/// as a primary action rather than another selectable contact.
class _AddPersonRow extends StatelessWidget {
  const _AddPersonRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm + 2,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  size: AppSizes.iconSm,
                  color: context.colors.brightness == Brightness.dark
                      ? context.colors.primary
                      : context.colors.onSurface,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add new person',
                      style: context.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      "Add someone who isn't listed",
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: AppSizes.iconSm,
                color: context.colors.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single selectable person row — flat by default, with a quiet ripple on
/// tap. There's no persistent "selected" treatment here: tapping a row
/// immediately resolves the picker (see [showPersonPickerSheet]), so there's
/// never a lingering selection state to render.
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          child: Row(
            children: [
              PersonAvatar(
                name: person.name,
                colorValue: person.avatarColorValue,
                radius: 20,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  person.name,
                  style: context.textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: context.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
