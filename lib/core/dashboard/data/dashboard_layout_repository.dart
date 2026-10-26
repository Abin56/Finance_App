import 'dart:convert';

import '../../../features/reports/domain/reports_period.dart';
import '../../services/local_settings_service.dart';
import '../domain/dashboard_widget.dart';
import '../domain/dashboard_widget_type.dart';
import '../domain/date_range_strategy.dart';
import '../domain/widget_configuration.dart';
import 'dashboard_layout_defaults.dart';

const _storageKey = 'dashboard_layouts_v1';
const _activeLayoutKey = 'dashboard_active_layout_id';

/// One-shot flag for [DashboardLayoutRepository._withQuickActions] — set the
/// first time a saved layout is checked for the Quick Actions widget, so a
/// user who later deletes that widget never has it silently re-added.
const _quickActionsMigrationKey = 'dashboard_quick_actions_added_v1';

/// One-shot flag for [DashboardLayoutRepository._withDashboardV2] — the
/// Dashboard 2.0 cleanup runs against a saved layout exactly once, so a user
/// who later removes the attention strip never has it silently re-added.
const _dashboardV2MigrationKey = 'dashboard_v2_layout_migrated_v1';

/// Everything [DashboardLayoutController] persists: every
/// [WidgetConfiguration] that exists (regardless of which layout references
/// it) plus every saved [DashboardLayout] profile.
class DashboardState {
  const DashboardState({
    required this.configs,
    required this.layouts,
    required this.activeLayoutId,
  });

  final Map<String, WidgetConfiguration> configs;
  final List<DashboardLayout> layouts;
  final String activeLayoutId;

  DashboardLayout get activeLayout => layouts.firstWhere(
    (l) => l.id == activeLayoutId,
    orElse: () => layouts.first,
  );

  DashboardState copyWith({
    Map<String, WidgetConfiguration>? configs,
    List<DashboardLayout>? layouts,
    String? activeLayoutId,
  }) {
    return DashboardState(
      configs: configs ?? this.configs,
      layouts: layouts ?? this.layouts,
      activeLayoutId: activeLayoutId ?? this.activeLayoutId,
    );
  }
}

/// Reads/writes the dashboard's widget layout and configuration as a single
/// JSON blob in [LocalSettingsService] — mirrors [FiscalYearController]'s
/// device-local persistence pattern. Device-local (not synced via Firestore)
/// is a deliberate starting point: syncing dashboard layout across a user's
/// devices can be added later as its own change without altering this
/// shape, since [DashboardState] doesn't assume where it's stored.
class DashboardLayoutRepository {
  const DashboardLayoutRepository();

  DashboardState load() {
    final raw = LocalSettingsService.getString(_storageKey);
    if (raw == null) return _defaultState();

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final configsJson = json['configs'] as Map<String, dynamic>;
      final configs = configsJson.map(
        (id, c) => MapEntry(
          id,
          WidgetConfiguration.fromJson(c as Map<String, dynamic>),
        ),
      );
      final layouts = (json['layouts'] as List<dynamic>)
          .map((l) => DashboardLayout.fromJson(l as Map<String, dynamic>))
          .toList();
      final activeLayoutId =
          LocalSettingsService.getString(_activeLayoutKey) ?? layouts.first.id;
      final state = DashboardState(
        configs: configs,
        layouts: layouts,
        activeLayoutId: activeLayoutId,
      );
      return _withDashboardV2(_withQuickActions(state));
    } catch (_) {
      // Corrupt or outdated shape (e.g. from a future format) — fall back
      // to defaults rather than crash the dashboard on startup.
      return _defaultState();
    }
  }

  Future<void> save(DashboardState state) async {
    final json = {
      'configs': state.configs.map((id, c) => MapEntry(id, c.toJson())),
      'layouts': state.layouts.map((l) => l.toJson()).toList(),
    };
    await LocalSettingsService.setString(_storageKey, jsonEncode(json));
    await LocalSettingsService.setString(
      _activeLayoutKey,
      state.activeLayoutId,
    );
  }

  /// Migration for layouts saved before the Quick Actions widget existed in
  /// the catalog's defaults: inserts one Quick Actions widget near the top of
  /// every saved layout, exactly once ([_quickActionsMigrationKey]), and
  /// persists the merged state immediately so later loads see it without
  /// depending on the flag. Runs only for saved blobs — a fresh install gets
  /// Quick Actions from [buildDefaultDashboard] directly.
  DashboardState _withQuickActions(DashboardState state) {
    if (LocalSettingsService.getBool(_quickActionsMigrationKey)) return state;
    // Fire-and-forget: load() is synchronous and SharedPreferences queues
    // writes, so the flag and merged blob land without blocking startup.
    LocalSettingsService.setBool(_quickActionsMigrationKey, true);

    final alreadyPresent = state.layouts.any(
      (l) => l.widgets.any((w) => w.type == DashboardWidgetType.quickActions),
    );
    if (alreadyPresent) return state;

    const config = 'quickActions';
    final migrated = state.copyWith(
      configs: {
        ...state.configs,
        config: WidgetConfiguration(
          id: config,
          type: DashboardWidgetType.quickActions,
          title: DashboardWidgetType.quickActions.defaultTitle,
        ),
      },
      layouts: [
        for (final layout in state.layouts)
          layout.copyWith(
            widgets: [...layout.widgets]
              ..insert(
                layout.widgets.length < 2 ? layout.widgets.length : 2,
                DashboardWidget(
                  id: 'w-quickActions-${layout.id}',
                  type: DashboardWidgetType.quickActions,
                  configId: config,
                ),
              ),
          ),
      ],
    );
    save(migrated);
    return migrated;
  }

  /// Dashboard 2.0 migration for saved layouts, additive and run once
  /// ([_dashboardV2MigrationKey]):
  ///  - drops placements of types with no renderer yet (Budget Health /
  ///    Goals), which only ever showed as a "Coming Soon" card — their
  ///    [WidgetConfiguration]s stay in `configs`, untouched;
  ///  - inserts one Needs Attention strip right under Net Worth (or at the
  ///    top when there is no Net Worth widget), in every layout without one;
  ///  - re-labels the untouched default Cash Flow config ("Today" on a
  ///    Today strategy) to the This-Month period the card actually shows.
  /// Every other widget keeps its order, visibility and settings.
  DashboardState _withDashboardV2(DashboardState state) {
    if (LocalSettingsService.getBool(_dashboardV2MigrationKey)) return state;
    LocalSettingsService.setBool(_dashboardV2MigrationKey, true);

    var configId = 'attention';
    final existingAttention = state.configs[configId];
    if (existingAttention != null &&
        existingAttention.type != DashboardWidgetType.attention) {
      configId = 'attention-v2';
    }
    final configs = {
      ...state.configs,
      configId:
          state.configs[configId] ??
          WidgetConfiguration(
            id: configId,
            type: DashboardWidgetType.attention,
            title: DashboardWidgetType.attention.defaultTitle,
          ),
    };
    for (final entry in state.configs.entries) {
      final c = entry.value;
      if (c.type == DashboardWidgetType.cashFlow &&
          c.title == 'Today' &&
          c.dateStrategy is ReportsPeriodStrategy &&
          (c.dateStrategy as ReportsPeriodStrategy).period ==
              ReportsPeriod.today) {
        configs[entry.key] = c.copyWith(
          title: 'Cash Flow',
          dateStrategy: const ReportsPeriodStrategy(ReportsPeriod.thisMonth),
        );
      }
    }

    final layouts = [
      for (final layout in state.layouts)
        layout.copyWith(widgets: _migrateWidgets(layout, configId)),
    ];
    final migrated = state.copyWith(configs: configs, layouts: layouts);
    save(migrated);
    return migrated;
  }

  List<DashboardWidget> _migrateWidgets(
    DashboardLayout layout,
    String configId,
  ) {
    final widgets = layout.widgets.where((w) => w.type.isBuilt).toList();
    if (widgets.any((w) => w.type == DashboardWidgetType.attention)) {
      return widgets;
    }
    final netWorthIndex = widgets.indexWhere(
      (w) => w.type == DashboardWidgetType.netWorth,
    );
    widgets.insert(
      netWorthIndex + 1,
      DashboardWidget(
        id: 'w-attention-${layout.id}',
        type: DashboardWidgetType.attention,
        configId: configId,
      ),
    );
    return widgets;
  }

  DashboardState _defaultState() {
    final defaults = buildDefaultDashboard();
    return DashboardState(
      configs: {for (final c in defaults.configs) c.id: c},
      layouts: defaults.layouts,
      activeLayoutId: defaults.layouts.first.id,
    );
  }
}
