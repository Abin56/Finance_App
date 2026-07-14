import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_settings_service.dart';

const _themeModeKey = 'theme_mode';

/// Persists the user's chosen [ThemeMode] locally so the preference
/// survives app restarts without becoming synced Firestore data.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = LocalSettingsService.getString(_themeModeKey);
    return _fromString(stored);
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    LocalSettingsService.setString(_themeModeKey, mode.name);
  }

  void toggle() {
    setThemeMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  ThemeMode _fromString(String? value) {
    return ThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ThemeMode.system,
    );
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
