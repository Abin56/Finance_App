import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/expense_status_pill.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../../transactions/domain/history_builder.dart';
import '../../domain/expense.dart';
import '../providers/expense_providers.dart';
import '../widgets/add_expense_chooser.dart';

/// Full split-expense list — every expense that was split or assigned to
/// someone, newest first. The FAB offers the two entry points from
/// Milestone 7: splitting a bill across several people, or assigning one
/// expense entirely to a single person.
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shared expenses')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'expenses_fab',
        onPressed: () => AddExpenseChooser.show(context),
        child: const Icon(Icons.add),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (expenses) {
          if (expenses.isEmpty) {
            return EmptyState(
              icon: Icons.call_split_rounded,
              title: 'No shared expenses yet',
              subtitle: 'Share a bill with friends or say who will pay an expense to start tracking it.',
              action: FilledButton(
                onPressed: () => AddExpenseChooser.show(context),
                child: const Text('Add your first shared expense'),
              ),
            );
          }

          final sorted = [...expenses]..sort((a, b) => b.date.compareTo(a.date));

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              for (final expense in sorted)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: _ExpenseTile(expense: expense),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participantNames = expense.participants.map((p) => p.name).join(', ');
    final installments = expense.scheduleId == null
        ? const <Installment>[]
        : ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final collected = installments.fold(0.0, (sum, i) => sum + i.amountPaid);
    final progress = expense.totalAmount <= 0 ? 0.0 : (collected / expense.totalAmount).clampedProgress;
    final detail = HistoryBuilder.splitExpenseDetailFor(
      expense,
      {if (expense.scheduleId != null) expense.scheduleId!: installments},
    );

    return AppCard(
      onTap: () => context.push('${AppRoutes.transactions}/${expense.transactionId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(expense.description, style: context.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      expense.participants.isEmpty ? expense.date.fullDate : 'With $participantNames',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.instance.format(expense.totalAmount),
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ExpenseStatusPill(status: detail.status),
                ],
              ),
            ],
          ),
          if (expense.participants.isNotEmpty) ...[
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                _AvatarStack(names: expense.participants.map((p) => p.name).toList()),
                const SizedBox(width: AppSizes.sm),
                Expanded(child: ProgressBar(progress: progress, height: 6)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Overlapping participant avatars — a compact "who's in this" glance
/// without spelling out every name, mirroring how premium finance apps
/// (Splitwise, Monarch) preview a split's people on the list row.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names});

  final List<String> names;

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold(0, (sum, c) => sum + c);
    return AppColors.categoryPalette[hash % AppColors.categoryPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    final overflow = names.length - shown.length;

    return SizedBox(
      height: 24,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 16.0,
              child: PersonAvatar(name: shown[i], colorValue: _colorFor(shown[i]).toARGB32(), radius: 12),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * 16.0,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: context.colors.surfaceContainerHighest,
                child: Text(
                  '+$overflow',
                  style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
