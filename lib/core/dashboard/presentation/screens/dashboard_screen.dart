import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../domain/dashboard_widget_type.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import '../providers/dashboard_layout_providers.dart';
import '../widgets/add_dashboard_widget_sheet.dart';
import '../widgets/coming_soon_widget_card.dart';
import '../widgets/dashboard_widget_registry.dart';
import '../widgets/dashboard_widget_shell.dart';
import '../widgets/financial_view_config_sheet.dart';
import '../widgets/greeting_header.dart';

/// The Dashboard tab, rebuilt on the widget-based architecture: renders
/// whatever the active [DashboardLayout] contains, in View Mode by default,
/// switching to Edit Mode (drag/reorder/hide/configure/remove, plus Add
/// Widget and Reset) when the user taps Edit. Every widget's own
/// render/calculation logic lives outside this file — see
/// [buildDashboardWidget] — so adding a new [DashboardWidgetType] never means
/// touching this screen.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  /// Content never stretches past a comfortable reading width on tablets /
  /// landscape; phones use the full width.
  static const _maxContentWidth = 720.0;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _editMode = false;

  /// Pull-to-refresh re-subscribes every Firestore stream the Dashboard is
  /// built on ([dashboardSourceStreams]) and waits for transactions — the
  /// widest of them — to answer again, so the spinner reflects real work.
  Future<void> _onRefresh() async {
    invalidateDashboardSources(ref);
    try {
      await ref
          .read(transactionsStreamProvider.future)
          .timeout(const Duration(seconds: 8));
    } on Object {
      // Timeout or stream error: each section shows its own error / retry.
    }
  }

  Future<void> _configure(WidgetConfiguration config) async {
    if (config.type != DashboardWidgetType.financialView) return;
    final updated = await FinancialViewConfigSheet.show(context, config);
    if (updated != null) {
      await ref
          .read(dashboardLayoutControllerProvider.notifier)
          .updateConfig(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    const listPadding = EdgeInsets.fromLTRB(
      AppSizes.lg,
      AppSizes.xs,
      AppSizes.lg,
      AppSizes.fabClearance,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DashboardScreen._maxContentWidth,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSizes.lg,
                    AppSizes.md,
                    AppSizes.md,
                    AppSizes.md,
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: GreetingHeader()),
                      const SizedBox(width: AppSizes.xs),
                      _EditToggle(
                        editMode: _editMode,
                        onPressed: () => setState(() => _editMode = !_editMode),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _editMode
                      ? _EditModeList(padding: listPadding)
                      : RefreshIndicator(
                          onRefresh: _onRefresh,
                          child: _ViewModeList(
                            padding: listPadding,
                            onConfigure: _configure,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditToggle extends StatelessWidget {
  const _EditToggle({required this.editMode, required this.onPressed});

  final bool editMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (editMode) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
        child: const Text('Done'),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.outline),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          Icons.tune_rounded,
          color: context.isDarkMode
              ? context.flowfi.heroAccent
              : colors.onSurface,
          size: AppSizes.iconSm,
        ),
        tooltip: 'Customize dashboard',
        style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
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
    // Built widgets render individually, in layout order; any not-yet-built
    // type still left in a layout is pulled out and rendered once at the
    // end as a single Coming Soon card instead of one placeholder per type.
    final built = [
      for (final entry in widgets)
        if (entry.$1.type.isBuilt) entry,
    ];
    final comingSoonTypes = [
      for (final entry in widgets)
        if (!entry.$1.type.isBuilt) entry.$1.type,
    ];

    if (built.isEmpty && comingSoonTypes.isEmpty) {
      return ListView(
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [_EmptyDashboard()],
      );
    }

    return ListView.separated(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: built.length + (comingSoonTypes.isEmpty ? 0 : 1),
      separatorBuilder: (_, index) => SizedBox(
        // The attention strip sits tight under the hero it qualifies.
        height:
            index + 1 < built.length &&
                built[index + 1].$1.type == DashboardWidgetType.attention
            ? AppSizes.sm
            : AppSizes.lg,
      ),
      itemBuilder: (context, index) {
        if (index == built.length) {
          return ComingSoonWidgetCard(types: comingSoonTypes);
        }
        final (widget, config) = built[index];
        return KeyedSubtree(
          key: ValueKey(widget.id),
          child: buildDashboardWidget(
            widget.type,
            config,
            onConfigure: widget.type == DashboardWidgetType.financialView
                ? () => onConfigure(config)
                : null,
          ),
        );
      },
    );
  }
}

/// Every widget removed or hidden — say so and offer the way back, rather
/// than an empty white screen.
class _EmptyDashboard extends ConsumerWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.xxxl),
      child: Column(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: AppSizes.iconXl,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(height: AppSizes.md),
          Text('Your dashboard is empty', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Add widgets back, or restore the default layout.',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSizes.lg),
          FilledButton.icon(
            onPressed: () => AddDashboardWidgetSheet.show(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add widget'),
          ),
        ],
      ),
    );
  }
}

class _EditModeList extends ConsumerWidget {
  const _EditModeList({required this.padding});

  final EdgeInsets padding;

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset dashboard?'),
        content: const Text(
          'This restores the default widgets and order for this dashboard. '
          'Your financial data is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(dashboardLayoutControllerProvider.notifier)
          .resetActiveLayoutToDefault();
    }
  }

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

    void remove(int index) {
      final removed = layout.widgets[index];
      final title = state.configs[removed.configId]?.title ?? 'Widget';
      unawaited(controller.removeWidget(removed.id));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$title removed'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => controller.insertWidget(removed, index),
            ),
          ),
        );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            0,
            AppSizes.lg,
            AppSizes.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => AddDashboardWidgetSheet.show(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add widget'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              OutlinedButton.icon(
                onPressed: () => _confirmReset(context, ref),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: padding,
            itemCount: layout.widgets.length,
            onReorderItem: (oldIndex, newIndex) =>
                controller.reorder(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final dashboardWidget = layout.widgets[index];
              final config = state.configs[dashboardWidget.configId];
              if (config == null) {
                return SizedBox.shrink(key: ValueKey(dashboardWidget.id));
              }
              return Padding(
                key: ValueKey(dashboardWidget.id),
                padding: const EdgeInsets.only(bottom: AppSizes.lg),
                child: DashboardWidgetEditFrame(
                  title: config.title,
                  isVisible: config.isVisible,
                  canConfigure:
                      config.type == DashboardWidgetType.financialView,
                  dragHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  onToggleVisibility: () =>
                      controller.setVisibility(config.id, !config.isVisible),
                  onConfigure: () => configure(config),
                  onDelete: () => remove(index),
                  child: buildDashboardWidget(dashboardWidget.type, config),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
