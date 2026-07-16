import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/states/money_direction_indicator.dart';
import '../../../../shared/widgets/states/shimmer_box.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import 'dashboard_preview_row.dart';
import 'dashboard_section_card.dart';

/// Top people who owe the user money ([creditorsProvider], already sorted
/// largest-first) — a per-person preview distinct from the Cash Flow
/// Center's category-level [MoneyToReceiveCard]. "View all" opens the full
/// Creditors list.
class DashboardMoneyToReceiveCard extends ConsumerWidget {
  const DashboardMoneyToReceiveCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleLoading = ref.watch(peopleStreamProvider).isLoading;
    if (peopleLoading) {
      return const DashboardSectionCard(child: _MoneyToReceiveSkeleton());
    }

    final creditors = ref.watch(creditorsProvider).take(3).toList();

    if (creditors.isEmpty) {
      return PlaceholderCard(
        icon: Icons.call_received_rounded,
        title: 'Nothing owed to you',
        message: 'People who owe you money will appear here.',
        radius: AppSizes.radiusCard,
        actionLabel: 'View People',
        onTap: () => context.push(AppRoutes.people),
      );
    }

    return DashboardSectionCard(
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

    return DashboardPreviewRow(
      leading: CircleAvatar(
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
      title: person.name,
      caption: 'Owes you',
      captionWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Owes you',
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSizes.xs),
          ProgressBar(progress: settledRatio, height: 6),
        ],
      ),
      amount: person.currentBalance,
      statusBadge: const MoneyDirectionBadge(direction: MoneyDirection.toReceive, compact: true),
      onTap: () => context.push('${AppRoutes.people}/${person.id}'),
    );
  }
}

class _MoneyToReceiveSkeleton extends StatelessWidget {
  const _MoneyToReceiveSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: AppSizes.md),
          Row(
            children: [
              const ShimmerBox(width: 44, height: 44, borderRadius: AppSizes.radiusPill),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(width: 120, height: 16),
                    SizedBox(height: AppSizes.xs),
                    ShimmerBox(width: 80, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              const ShimmerBox(width: 60, height: 16),
            ],
          ),
        ],
      ],
    );
  }
}
