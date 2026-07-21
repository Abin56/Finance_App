import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/dashboard/data/dashboard_layout_repository.dart';
import 'package:finance_app/core/dashboard/domain/dashboard_widget.dart';
import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/services/local_settings_service.dart';

/// A minimal pre-Quick-Actions saved blob: one layout with a single Net
/// Worth widget, saved before the quickActions type existed in defaults.
String _legacyBlob() {
  final config = WidgetConfiguration(
    id: 'netWorth',
    type: DashboardWidgetType.netWorth,
    title: 'Net Worth',
  );
  final layout = DashboardLayout(
    id: 'personal',
    name: 'Personal',
    widgets: const [
      DashboardWidget(id: 'w-netWorth', type: DashboardWidgetType.netWorth, configId: 'netWorth'),
    ],
  );
  return jsonEncode({
    'configs': {'netWorth': config.toJson()},
    'layouts': [layout.toJson()],
  });
}

void main() {
  setUp(() async {
    LocalSettingsService.resetForTest();
    SharedPreferences.setMockInitialValues({'dashboard_layouts_v1': _legacyBlob()});
    await LocalSettingsService.init();
  });

  test('saved layout without Quick Actions gets it inserted once', () {
    const repository = DashboardLayoutRepository();
    final state = repository.load();

    final quickActions = state.activeLayout.widgets.where((w) => w.type == DashboardWidgetType.quickActions);
    expect(quickActions, hasLength(1));
    expect(state.configs[quickActions.single.configId]?.type, DashboardWidgetType.quickActions);
  });

  test('deleting Quick Actions after migration is respected on the next load', () async {
    const repository = DashboardLayoutRepository();
    final migrated = repository.load();
    expect(
      migrated.activeLayout.widgets.any((w) => w.type == DashboardWidgetType.quickActions),
      isTrue,
    );

    // Simulate the user deleting the widget in Edit Mode (controller
    // persists the layout minus that slot).
    final layout = migrated.activeLayout;
    final withoutQuickActions = migrated.copyWith(
      layouts: [
        layout.copyWith(
          widgets: layout.widgets.where((w) => w.type != DashboardWidgetType.quickActions).toList(),
        ),
      ],
    );
    await repository.save(withoutQuickActions);

    final reloaded = repository.load();
    expect(
      reloaded.activeLayout.widgets.any((w) => w.type == DashboardWidgetType.quickActions),
      isFalse,
    );
  });
}
