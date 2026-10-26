import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/dashboard_widget.dart';
import '../../domain/dashboard_widget_type.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_layout_providers.dart';

/// "Add widget" — every built [DashboardWidgetType], each showing whether it
/// is already on the active layout. Adding seeds the new instance from the
/// type's default configuration (see `defaultConfigFor`); a single-instance
/// widget that's present but hidden is offered as "Show" instead of a
/// duplicate. This is the way back for a removed widget.
class AddDashboardWidgetSheet extends ConsumerWidget {
  const AddDashboardWidgetSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddDashboardWidgetSheet(),
    );
  }

  static const _icons = <DashboardWidgetType, IconData>{
    DashboardWidgetType.netWorth: Icons.account_balance_rounded,
    DashboardWidgetType.attention: Icons.notification_important_outlined,
    DashboardWidgetType.previousCycleCarryForward: Icons.history_rounded,
    DashboardWidgetType.cashFlow: Icons.swap_vert_rounded,
    DashboardWidgetType.quickActions: Icons.bolt_rounded,
    DashboardWidgetType.upcomingPayments: Icons.event_rounded,
    DashboardWidgetType.financialView: Icons.insights_rounded,
    DashboardWidgetType.expenseComparison: Icons.compare_arrows_rounded,
    DashboardWidgetType.accounts: Icons.account_balance_wallet_outlined,
    DashboardWidgetType.spendingCategories: Icons.pie_chart_outline_rounded,
    DashboardWidgetType.creditUtilization: Icons.speed_rounded,
    DashboardWidgetType.creditCards: Icons.credit_card_rounded,
    DashboardWidgetType.people: Icons.people_outline_rounded,
    DashboardWidgetType.recentActivity: Icons.receipt_long_outlined,
    DashboardWidgetType.insights: Icons.lightbulb_outline_rounded,
    DashboardWidgetType.bills: Icons.bolt_outlined,
    DashboardWidgetType.emi: Icons.calendar_month_rounded,
    DashboardWidgetType.loans: Icons.account_balance_outlined,
    DashboardWidgetType.splitExpenses: Icons.call_split_rounded,
    DashboardWidgetType.calendar: Icons.calendar_today_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardLayoutControllerProvider);
    final controller = ref.read(dashboardLayoutControllerProvider.notifier);
    final placed = state.activeLayout.widgets;
    final types = [
      for (final t in _icons.keys)
        if (t.isBuilt) t,
      for (final t in DashboardWidgetType.values)
        if (t.isBuilt && !_icons.containsKey(t)) t,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSizes.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.lg,
                0,
                AppSizes.lg,
                AppSizes.sm,
              ),
              child: Text('Add widget', style: context.textTheme.titleMedium),
            ),
            for (final type in types)
              _row(context, type, placed, state.configs, controller),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    DashboardWidgetType type,
    List<DashboardWidget> placed,
    Map<String, WidgetConfiguration> configs,
    DashboardLayoutController controller,
  ) {
    final instances = [
      for (final w in placed)
        if (w.type == type) w,
    ];
    final multi = type.supportsMultipleInstances;
    final hiddenConfigId = instances
        .map((w) => w.configId)
        .where((id) => configs[id]?.isVisible == false)
        .firstOrNull;
    final present = instances.isNotEmpty;

    final String status;
    final VoidCallback? onTap;
    if (!multi && present && hiddenConfigId != null) {
      status = 'Hidden · tap to show';
      onTap = () {
        controller.setVisibility(hiddenConfigId, true);
        Navigator.of(context).pop();
      };
    } else if (!multi && present) {
      status = 'On your dashboard';
      onTap = null;
    } else {
      status = multi && present
          ? '${instances.length} on your dashboard · add another'
          : 'Adds to the end — drag to reorder';
      onTap = () {
        controller.addWidget(type);
        Navigator.of(context).pop();
      };
    }

    return ListTile(
      leading: Icon(_icons[type] ?? Icons.widgets_outlined),
      title: Text(type.defaultTitle),
      subtitle: Text(status),
      enabled: onTap != null,
      trailing: onTap == null
          ? const Icon(Icons.check_rounded)
          : const Icon(Icons.add_rounded),
      onTap: onTap,
    );
  }
}
