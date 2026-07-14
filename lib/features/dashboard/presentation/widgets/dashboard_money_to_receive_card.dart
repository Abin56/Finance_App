import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';

/// Top people who owe the user money ([creditorsProvider], already sorted
/// largest-first) — a per-person preview distinct from the Cash Flow
/// Center's category-level [MoneyToReceiveCard]. "View all" opens the full
/// Creditors list.
class DashboardMoneyToReceiveCard extends ConsumerWidget {
  const DashboardMoneyToReceiveCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditors = ref.watch(creditorsProvider).take(3).toList();

    if (creditors.isEmpty) {
      return const PlaceholderCard(
        icon: Icons.call_received_rounded,
        title: 'Nothing owed to you',
        message: 'People who owe you money will appear here.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final person in creditors) _PersonRow(person: person),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final settledRatio = person.openingBalance == 0
        ? 0.0
        : ((person.openingBalance - person.currentBalance).abs() / person.openingBalance.abs());
    final initial = person.name.isEmpty ? '?' : person.name[0].toUpperCase();

    return InkWell(
      onTap: () => context.push('${AppRoutes.people}/${person.id}'),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Color(person.avatarColorValue).withValues(alpha: 0.18),
              child: Text(
                initial,
                style: context.textTheme.titleMedium?.copyWith(
                  color: Color(person.avatarColorValue),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: context.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    'Owes you',
                    style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  ProgressBar(progress: settledRatio, height: 6),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.instance.format(person.currentBalance),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const MoneyDirectionBadge(direction: MoneyDirection.toReceive, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
