import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../providers/people_providers.dart';
import '../widgets/person_tile.dart';

/// People you owe money to — a filtered view over the same people
/// collection [PeopleScreen] manages, sorted largest-owed-first.
class DebtorsScreen extends ConsumerWidget {
  const DebtorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtors = ref.watch(debtorsProvider);
    final totalPayable = ref.watch(totalPayableProvider);
    final peopleAsync = ref.watch(peopleStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('People I Need to Pay')),
      body: peopleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (_) {
          if (debtors.isEmpty) {
            return const EmptyState(
              icon: Icons.arrow_upward_rounded,
              title: 'You don\'t owe anyone',
              subtitle: 'People you owe money to will appear here.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total money to pay',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      CurrencyFormatter.instance.format(totalPayable),
                      style: context.textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              for (final person in debtors)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: PersonTile(
                    person: person,
                    onTap: () => context.push('${AppRoutes.people}/${person.id}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
