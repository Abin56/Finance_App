import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../features/expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../../features/people/domain/person.dart';
import '../../../../features/people/presentation/providers/people_providers.dart';
import '../../../../features/people/presentation/widgets/person_avatar.dart';
import '../../../../features/people/presentation/widgets/settle_up_sheet.dart';
import '../../../../features/transactions/domain/transaction_type.dart';
import '../../../../features/transactions/presentation/screens/add_expense_screen.dart';
import '../../domain/widget_configuration.dart';

/// Renders [DashboardWidgetType.quickActions] — the dashboard's four
/// highest-frequency actions as equal-width tiles: Add Expense, Settle Up,
/// Split Expense, Statements. Settle Up first asks which person to settle
/// with (only people who actually have a pending balance are offered), then
/// hands off to the existing [SettleUpSheet]; nothing here re-implements any
/// settlement or split machinery.
class QuickActionsWidgetCard extends ConsumerWidget {
  const QuickActionsWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  Future<void> _settleUp(BuildContext context, WidgetRef ref) async {
    // Debtors first (money you owe is usually the more urgent side), then
    // creditors — both already sorted largest-balance-first by their
    // providers.
    final people = [...ref.read(debtorsProvider), ...ref.read(creditorsProvider)];
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All settled — no pending balances with anyone.')),
      );
      return;
    }
    final person = await _SettleUpPersonSheet.show(context, people);
    if (person == null || !context.mounted) return;
    await SettleUpSheet.show(context, person);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.remove_circle_outline_rounded,
            label: 'Add Expense',
            color: AppColors.expense,
            onTap: () => AddExpenseScreen.show(context, initialType: TransactionType.expense),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _ActionTile(
            icon: Icons.handshake_outlined,
            label: 'Settle Up',
            color: AppColors.income,
            onTap: () => _settleUp(context, ref),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _ActionTile(
            icon: Icons.call_split_rounded,
            label: 'Split Expense',
            color: context.colors.primary,
            onTap: () => SplitExpenseFormSheet.show(context),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _ActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'Statements',
            color: AppColors.pending,
            onTap: () => context.push(AppRoutes.creditCards),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: AppShadows.soft(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.md, horizontal: AppSizes.xs),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  label,
                  style: context.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Settle up with whom?" — lists only people with a non-zero balance,
/// each labeled with the direction and amount pending, and resolves to the
/// tapped [Person] (or null when dismissed).
class _SettleUpPersonSheet extends StatelessWidget {
  const _SettleUpPersonSheet({required this.people});

  final List<Person> people;

  static Future<Person?> show(BuildContext context, List<Person> people) {
    return showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SettleUpPersonSheet(people: people),
    );
  }

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final textTheme = context.textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.sm),
              child: Text('Settle up with…', style: textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final person in people)
                    ListTile(
                      leading: PersonAvatar(name: person.name, colorValue: person.avatarColorValue),
                      title: Text(person.name),
                      subtitle: Text(
                        person.isDebtor
                            ? 'You owe ${format.format(person.currentBalance.abs())}'
                            : 'Owes you ${format.format(person.currentBalance)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: person.isDebtor ? AppColors.expense : AppColors.income,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(person),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
