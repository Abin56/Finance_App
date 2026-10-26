import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/dashboard/data/dashboard_layout_defaults.dart';
import 'package:finance_app/core/dashboard/data/dashboard_layout_repository.dart';
import 'package:finance_app/core/dashboard/domain/dashboard_widget.dart';
import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/date_range_strategy.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/dashboard/presentation/providers/dashboard_layout_providers.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';

/// Dashboard 2.0 layout migration (B4) + Add Widget / Undo / Reset (B3).
///
/// The saved blob below is a customized pre-2.0 layout: user-reordered,
/// one widget hidden, and the two never-built types (Budget Health, Goals)
/// that only ever rendered as a "Coming Soon" card.
WidgetConfiguration _config(
  String id,
  DashboardWidgetType type, {
  String? title,
  bool isVisible = true,
  DateRangeStrategy? strategy,
}) => WidgetConfiguration(
  id: id,
  type: type,
  title: title ?? type.defaultTitle,
  isVisible: isVisible,
  dateStrategy:
      strategy ?? const ReportsPeriodStrategy(ReportsPeriod.thisMonth),
);

String _customizedLegacyBlob() {
  final configs = [
    _config('people', DashboardWidgetType.people),
    _config('netWorth', DashboardWidgetType.netWorth),
    _config('budgetProgress', DashboardWidgetType.budgetProgress),
    _config(
      'cashFlow',
      DashboardWidgetType.cashFlow,
      title: 'Today',
      strategy: const ReportsPeriodStrategy(ReportsPeriod.today),
    ),
    _config('accounts', DashboardWidgetType.accounts, isVisible: false),
    _config('savingsGoals', DashboardWidgetType.savingsGoals),
    _config('quickActions', DashboardWidgetType.quickActions),
  ];
  final layout = DashboardLayout(
    id: 'personal',
    name: 'Personal',
    widgets: [
      for (final c in configs)
        DashboardWidget(id: 'w-${c.id}', type: c.type, configId: c.id),
    ],
  );
  return jsonEncode({
    'configs': {for (final c in configs) c.id: c.toJson()},
    'layouts': [layout.toJson()],
  });
}

List<DashboardWidgetType> _types(DashboardState s) =>
    s.activeLayout.widgets.map((w) => w.type).toList();

void main() {
  Future<void> seed(Map<String, Object> values) async {
    LocalSettingsService.resetForTest();
    SharedPreferences.setMockInitialValues(values);
    await LocalSettingsService.init();
  }

  group('B4 — saved-layout migration', () {
    setUp(
      () => seed({
        'dashboard_layouts_v1': _customizedLegacyBlob(),
        // Quick Actions is already present; mark its own migration done so
        // this group isolates the 2.0 migration.
        'dashboard_quick_actions_added_v1': true,
      }),
    );

    test('drops only unbuilt placements and keeps the user order', () {
      final state = const DashboardLayoutRepository().load();
      expect(_types(state), [
        DashboardWidgetType.people,
        DashboardWidgetType.netWorth,
        DashboardWidgetType.attention, // inserted right under Net Worth
        DashboardWidgetType.cashFlow,
        DashboardWidgetType.accounts,
        DashboardWidgetType.quickActions,
      ]);
      // Their configurations are not destroyed.
      expect(state.configs['budgetProgress'], isNotNull);
      expect(state.configs['savingsGoals'], isNotNull);
    });

    test('keeps visibility and relabels only the untouched "Today" cash '
        'flow default', () {
      final state = const DashboardLayoutRepository().load();
      expect(state.configs['accounts']!.isVisible, isFalse);
      final cashFlow = state.configs['cashFlow']!;
      expect(cashFlow.title, 'Cash Flow');
      expect(
        (cashFlow.dateStrategy as ReportsPeriodStrategy).period,
        ReportsPeriod.thisMonth,
      );
    });

    test('runs once: a removed attention strip is not re-added', () async {
      const repository = DashboardLayoutRepository();
      final migrated = repository.load();
      final layout = migrated.activeLayout;
      await repository.save(
        migrated.copyWith(
          layouts: [
            layout.copyWith(
              widgets: layout.widgets
                  .where((w) => w.type != DashboardWidgetType.attention)
                  .toList(),
            ),
          ],
        ),
      );
      expect(
        _types(repository.load()).contains(DashboardWidgetType.attention),
        isFalse,
      );
    });

    test('a saved custom cash flow title is left alone', () async {
      final blob = jsonDecode(_customizedLegacyBlob()) as Map<String, dynamic>;
      (blob['configs'] as Map<String, dynamic>)['cashFlow'] = _config(
        'cashFlow',
        DashboardWidgetType.cashFlow,
        title: 'My Money This Month',
      ).toJson();
      await seed({
        'dashboard_layouts_v1': jsonEncode(blob),
        'dashboard_quick_actions_added_v1': true,
      });
      final state = const DashboardLayoutRepository().load();
      expect(state.configs['cashFlow']!.title, 'My Money This Month');
    });
  });

  test('fresh defaults contain only built widget types', () {
    final defaults = buildDefaultDashboard();
    for (final w in defaults.layouts.single.widgets) {
      expect(w.type.isBuilt, isTrue, reason: '${w.type} would be Coming Soon');
    }
    final types = defaults.layouts.single.widgets.map((w) => w.type);
    expect(types.first, DashboardWidgetType.netWorth);
    expect(types.elementAt(1), DashboardWidgetType.attention);
    expect(types, contains(DashboardWidgetType.spendingCategories));
    expect(types, contains(DashboardWidgetType.creditUtilization));
  });

  group('B3 — Add widget / Undo / Reset', () {
    late ProviderContainer container;

    setUp(() async {
      await seed({});
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    DashboardLayoutController controller() =>
        container.read(dashboardLayoutControllerProvider.notifier);
    DashboardState state() => container.read(dashboardLayoutControllerProvider);

    test(
      'a removed widget can be added back, seeded from its default',
      () async {
        final previousCycle = state().activeLayout.widgets.firstWhere(
          (w) => w.type == DashboardWidgetType.previousCycleCarryForward,
        );
        await controller().removeWidget(previousCycle.id);
        expect(
          _types(state()),
          isNot(contains(DashboardWidgetType.previousCycleCarryForward)),
        );

        await controller().addWidget(
          DashboardWidgetType.previousCycleCarryForward,
        );
        final readded = state().activeLayout.widgets.last;
        expect(readded.type, DashboardWidgetType.previousCycleCarryForward);
        // Seeded from the default config, not bare defaults.
        expect(
          state().configs[readded.configId]!.dateStrategy,
          isA<SalaryCycleToDate>(),
        );
      },
    );

    test('Undo puts the slot back where it was, same config', () async {
      final before = state().activeLayout.widgets;
      final removed = before[3];
      await controller().removeWidget(removed.id);
      await controller().insertWidget(removed, 3);
      expect(
        state().activeLayout.widgets.map((w) => w.id),
        before.map((w) => w.id),
      );
    });

    test('Reset restores the default arrangement', () async {
      final defaults = buildDefaultDashboard().layouts.single.widgets;
      await controller().reorder(0, 5);
      await controller().removeWidget(state().activeLayout.widgets.first.id);
      await controller().resetActiveLayoutToDefault();
      expect(
        state().activeLayout.widgets.map((w) => w.id),
        defaults.map((w) => w.id),
      );
    });
  });
}
