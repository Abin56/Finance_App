import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_settings_service.dart';

const _fiscalYearStartMonthKey = 'fiscal_year_start_month';

/// Persists the user's chosen financial-year start month (1-12) locally,
/// mirroring [ThemeModeController]. Defaults to January (calendar year),
/// but stays configurable — e.g. April for the Indian financial year
/// convention — since [ReportsPeriod.financialYear] reads this rather than
/// hardcoding a start month.
class FiscalYearController extends Notifier<int> {
  @override
  int build() => LocalSettingsService.getInt(_fiscalYearStartMonthKey, defaultValue: 1);

  Future<void> setStartMonth(int month) async {
    assert(month >= 1 && month <= 12);
    state = month;
    await LocalSettingsService.setInt(_fiscalYearStartMonthKey, month);
  }
}

final fiscalYearStartMonthProvider = NotifierProvider<FiscalYearController, int>(
  FiscalYearController.new,
);
