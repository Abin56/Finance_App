import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/dashboard_layout_repository.dart';
import '../../domain/dashboard_widget.dart';
import '../../domain/dashboard_widget_type.dart';
import '../../domain/widget_configuration.dart';

final dashboardLayoutRepositoryProvider = Provider<DashboardLayoutRepository>((ref) {
  return const DashboardLayoutRepository();
});

/// Owns the dashboard's widget layout and per-widget configuration —
/// everything Edit Mode mutates. Every method here persists immediately via
/// [DashboardLayoutRepository.save] rather than requiring an explicit "Save"
/// step, matching how every other settings screen in the app behaves.
class DashboardLayoutController extends Notifier<DashboardState> {
  static const _uuid = Uuid();

  @override
  DashboardState build() => ref.watch(dashboardLayoutRepositoryProvider).load();

  Future<void> _persist(DashboardState next) async {
    state = next;
    await ref.read(dashboardLayoutRepositoryProvider).save(next);
  }

  /// Moves the widget at [oldIndex] to [newIndex] within the active layout —
  /// Edit Mode's drag-to-reorder. Both indices are already post-removal-
  /// adjusted (as `ReorderableListView.onReorderItem` reports them), so the
  /// item is simply removed then reinserted at [newIndex] with no further
  /// off-by-one correction.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final layout = state.activeLayout;
    final widgets = [...layout.widgets];
    final widget = widgets.removeAt(oldIndex);
    widgets.insert(newIndex, widget);
    await _updateActiveLayout(layout.copyWith(widgets: widgets));
  }

  Future<void> setVisibility(String configId, bool isVisible) async {
    final config = state.configs[configId];
    if (config == null) return;
    await _updateConfig(config.copyWith(isVisible: isVisible));
  }

  Future<void> updateConfig(WidgetConfiguration updated) async {
    await _updateConfig(updated);
  }

  /// Removes a widget slot from the active layout — the underlying
  /// [WidgetConfiguration] is left in [DashboardState.configs] (harmless if
  /// unreferenced) so undoing a delete is possible later without having lost
  /// its settings; only the layout's placement is what "delete" removes.
  Future<void> removeWidget(String dashboardWidgetId) async {
    final layout = state.activeLayout;
    final widgets = layout.widgets.where((w) => w.id != dashboardWidgetId).toList();
    await _updateActiveLayout(layout.copyWith(widgets: widgets));
  }

  /// Adds a new widget instance of [type] to the end of the active layout,
  /// with a fresh [WidgetConfiguration] seeded from [seed] (or a bare
  /// default if omitted) — how "Add Widget" and "Duplicate" both work, since
  /// duplicating is just adding with the existing config as the seed.
  Future<void> addWidget(DashboardWidgetType type, {WidgetConfiguration? seed}) async {
    final configId = _uuid.v4();
    final widgetId = _uuid.v4();
    final source = seed ?? WidgetConfiguration(id: configId, type: type, title: type.defaultTitle);
    final configWithId = WidgetConfiguration(
      id: configId,
      type: type,
      title: source.title,
      dateStrategy: source.dateStrategy,
      financialViewModule: source.financialViewModule,
      size: source.size,
      isVisible: true,
      accountIds: source.accountIds,
      categoryIds: source.categoryIds,
      personIds: source.personIds,
    );

    final layout = state.activeLayout;
    final widgets = [...layout.widgets, DashboardWidget(id: widgetId, type: type, configId: configId)];

    await _persist(
      state.copyWith(
        configs: {...state.configs, configId: configWithId},
        layouts: [
          for (final l in state.layouts) l.id == layout.id ? layout.copyWith(widgets: widgets) : l,
        ],
      ),
    );
  }

  Future<void> _updateConfig(WidgetConfiguration updated) async {
    await _persist(state.copyWith(configs: {...state.configs, updated.id: updated}));
  }

  Future<void> _updateActiveLayout(DashboardLayout updated) async {
    await _persist(
      state.copyWith(
        layouts: [for (final l in state.layouts) l.id == updated.id ? updated : l],
      ),
    );
  }
}

final dashboardLayoutControllerProvider = NotifierProvider<DashboardLayoutController, DashboardState>(
  DashboardLayoutController.new,
);

/// The active layout's widgets, each paired with its resolved
/// [WidgetConfiguration] — what the dashboard shell actually renders.
/// Excludes hidden widgets in View Mode; Edit Mode reads
/// [dashboardLayoutControllerProvider] directly so it can still show hidden
/// widgets (dimmed) for un-hiding.
final visibleDashboardWidgetsProvider = Provider<List<(DashboardWidget, WidgetConfiguration)>>((ref) {
  final state = ref.watch(dashboardLayoutControllerProvider);
  final result = <(DashboardWidget, WidgetConfiguration)>[];
  for (final widget in state.activeLayout.widgets) {
    final config = state.configs[widget.configId];
    if (config == null || !config.isVisible) continue;
    result.add((widget, config));
  }
  return result;
});
