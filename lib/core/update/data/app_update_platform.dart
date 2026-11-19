import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper over the `finance_app/app_update` channel in MainActivity.
/// Every call fails closed/soft: off Android, in a test, or on any channel
/// error, self-update is simply reported as unsupported.
class AppUpdatePlatform {
  const AppUpdatePlatform();

  static const MethodChannel _channel = MethodChannel('finance_app/app_update');

  /// True only for builds whose merged manifest declares
  /// REQUEST_INSTALL_PACKAGES — i.e. the `sideload` flavor. The `play` flavor
  /// removes it, so a Play build never offers to self-install an APK.
  Future<bool> isSelfUpdateSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isSelfUpdateSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether Android currently lets FlowFi hand an APK to the installer
  /// ("Install unknown apps" for this app).
  Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens FlowFi's own "Install unknown apps" settings page.
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }
}
