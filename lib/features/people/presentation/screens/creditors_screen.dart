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

/// People who owe you money — a filtered view over the same people
/// collection [PeopleScreen] manages, sorted largest-owed-first.
class CreditorsScreen extends ConsumerWidget {
  const CreditorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditors = ref.watch(creditorsProvider);
    final totalReceivable = ref.watch(totalReceivableProvider);
    final peopleAsync = ref.watch(peopleStreamProvider);

    return Scaffold(
      
      appBar: AppBar(title: const Text('People Who Need to Pay Me')),
      body: peopleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (_) {
          if (creditors.isEmpty) {
            return const EmptyState(
              icon: Icons.arrow_downward_rounded,
              title: 'No one owes you',
              subtitle: 'People who owe you money will appear here.',
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
                      'Total money to receive',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      CurrencyFormatter.instance.format(totalReceivable),
                      style: context.textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              for (final person in creditors)
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
