import 'package:finance_app/core/services/fiscal_year_controller.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  test('defaults to January (1) when unset', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(fiscalYearStartMonthProvider), 1);
  });

  test('setStartMonth persists and updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fiscalYearStartMonthProvider.notifier).setStartMonth(4);

    expect(container.read(fiscalYearStartMonthProvider), 4);
    expect(LocalSettingsService.getInt('fiscal_year_start_month'), 4);
  });

  test('reads back a previously persisted value on a fresh container', () async {
    final first = ProviderContainer();
    await first.read(fiscalYearStartMonthProvider.notifier).setStartMonth(7);
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(second.read(fiscalYearStartMonthProvider), 7);
  });
}
