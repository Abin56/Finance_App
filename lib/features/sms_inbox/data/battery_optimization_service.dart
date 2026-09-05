import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/battery_optimization_availability.dart';

/// Wraps `MainActivity`'s `isBatteryUnrestricted`/`requestBatteryUnrestricted`
/// method-channel handlers behind [BatteryOptimizationAvailability]. Shares
/// the same channel as [NotificationAccessService] — both are native checks
/// feeding the same "is RCS capture actually going to work" concern, not two
/// independent features.
class BatteryOptimizationService {
  const BatteryOptimizationService();

  static const MethodChannel _channel = MethodChannel(
    'finance_app/notification_listener',
  );

  Future<BatteryOptimizationAvailability> checkStatus() async {
    if (!Platform.isAndroid) {
      return BatteryOptimizationAvailability.unsupportedPlatform;
    }
    final unrestricted =
        await _channel.invokeMethod<bool>('isBatteryUnrestricted') ?? false;
    return unrestricted
        ? BatteryOptimizationAvailability.unrestricted
        : BatteryOptimizationAvailability.restricted;
  }

  /// Launches the system's direct "Allow [app] to ignore battery
  /// optimizations?" dialog — the actual OS-level control an OEM's own
  /// per-app battery page (Samsung's Unrestricted/Optimised/Restricted
  /// picker, say) is itself just a UI over.
  Future<void> requestUnrestricted() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestBatteryUnrestricted');
  }
}
