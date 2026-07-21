import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../features/dashboard/presentation/widgets/greeting_header.dart';
import '../../domain/dashboard_widget_type.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_layout_providers.dart';
import '../widgets/coming_soon_widget_card.dart';
import '../widgets/dashboard_widget_registry.dart';
import '../widgets/dashboard_widget_shell.dart';
import '../widgets/financial_view_config_sheet.dart';

/// The Dashboard tab, rebuilt on the widget-based architecture: renders
/// whatever the active [DashboardLayout] contains, in View Mode by default,
/// switching to Edit Mode (drag/reorder/hide/configure/delete) when the user
/// taps Edit. Every widget's own render/calculation logic lives outside this
/// file — see [buildDashboardWidget] — so adding a new [DashboardWidgetType]
/// never means touching this screen.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _editMode = false;

  Future<void> _onRefresh() async {
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _configure(WidgetConfiguration config) async {
    if (config.type != DashboardWidgetType.financialView) return;
    final updated = await FinancialViewConfigSheet.show(context, config);
    if (updated != null) {
      await ref.read(dashboardLayoutControllerProvider.notifier).updateConfig(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    const listPadding = EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.fabClearance);

    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.primary.withValues(alpha: 0.06), colors.primary.withValues(alpha: 0)],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.lg),
              child: Row(
                children: [
                  const Expanded(child: GreetingHeader()),
                  const SizedBox(width: AppSizes.sm),
                  IconButton.filledTonal(
                    onPressed: () => setState(() => _editMode = !_editMode),
                    icon: Icon(_editMode ? Icons.check : Icons.edit_outlined),
                    tooltip: _editMode ? 'Done' : 'Edit Dashboard',
                    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: _editMode
                    ? _EditModeList(padding: listPadding)
                    : _ViewModeList(padding: listPadding, onConfigure: _configure),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewModeList extends ConsumerWidget {
  const _ViewModeList({required this.padding, required this.onConfigure});

  final EdgeInsets padding;
  final void Function(WidgetConfiguration) onConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(visibleDashboardWidgetsProvider);
    // Built widgets render individually, in layout order; every not-yet-built
    // type is pulled out and rendered once at the end as a single Coming
    // Soon card instead of one placeholder card per type.
    final built = [
      for (final entry in widgets)
        if (entry.$1.type.isBuilt) entry,
    ];
    final comingSoonTypes = [
      for (final entry in widgets)
        if (!entry.$1.type.isBuilt) entry.$1.type,
    ];

    return ListView.separated(
      padding: padding,
      itemCount: built.length + (comingSoonTypes.isEmpty ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: AppSizes.lg),
      itemBuilder: (context, index) {
        if (index == built.length) {
          return ComingSoonWidgetCard(types: comingSoonTypes);
        }
        final (widget, config) = built[index];
        return buildDashboardWidget(
          widget.type,
          config,
          onConfigure: widget.type == DashboardWidgetType.financialView ? () => onConfigure(config) : null,
        );
      },
    );
  }
}

class _EditModeList extends ConsumerWidget {
  const _EditModeList({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardLayoutControllerProvider);
    final controller = ref.read(dashboardLayoutControllerProvider.notifier);
    final layout = state.activeLayout;

    Future<void> configure(WidgetConfiguration config) async {
      if (config.type != DashboardWidgetType.financialView) return;
      final updated = await FinancialViewConfigSheet.show(context, config);
      if (updated != null) await controller.updateConfig(updated);
    }

    return ReorderableListView.builder(
      padding: padding,
      itemCount: layout.widgets.length,
      onReorderItem: (oldIndex, newIndex) => controller.reorder(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final dashboardWidget = layout.widgets[index];
        final config = state.configs[dashboardWidget.configId];
        if (config == null) return const SizedBox.shrink(key: ValueKey('missing'));
        return Padding(
          key: ValueKey(dashboardWidget.id),
          padding: const EdgeInsets.only(bottom: AppSizes.lg),
          child: DashboardWidgetEditFrame(
            title: config.title,
            isVisible: config.isVisible,
            dragHandle: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
            onToggleVisibility: () => controller.setVisibility(config.id, !config.isVisible),
            onConfigure: () => configure(config),
            onDelete: () => controller.removeWidget(dashboardWidget.id),
            child: buildDashboardWidget(dashboardWidget.type, config),
          ),
        );
      },
    );
  }
}
