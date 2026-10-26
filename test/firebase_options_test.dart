import 'package:finance_app/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins which Firebase app each platform initialises with (financeapp-585eb), so a
/// `flutterfire configure` run that drops platforms — as the Android-only run did on
/// 2026-10-25 — fails here instead of at app start.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  optionsFor(TargetPlatform p) {
    debugDefaultTargetPlatformOverride = p;
    return DefaultFirebaseOptions.currentPlatform;
  }

  test('Android uses the com.flowfi.app Firebase app', () {
    final o = optionsFor(TargetPlatform.android);
    expect(o.projectId, 'financeapp-585eb');
    expect(o.appId, '1:570188084565:android:141e0df6573ce52b25ebdc');
    expect(o.apiKey, isNotEmpty);
  });

  test('Windows uses its registered Firebase web app', () {
    final o = optionsFor(TargetPlatform.windows);
    expect(o.projectId, 'financeapp-585eb');
    expect(o.appId, '1:570188084565:web:2c1351d50b62789325ebdc');
  });

  test('web options point at the finance_app (web) registration', () {
    expect(DefaultFirebaseOptions.web.projectId, 'financeapp-585eb');
    expect(DefaultFirebaseOptions.web.appId, '1:570188084565:web:8016cc26cc7e9c1225ebdc');
    expect(DefaultFirebaseOptions.web.authDomain, 'financeapp-585eb.firebaseapp.com');
  });

  test('iOS, macOS and Linux have no registered Firebase app and say so instead of guessing', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.linux]) {
      expect(() => optionsFor(p), throwsUnsupportedError, reason: '$p');
    }
  });
}
