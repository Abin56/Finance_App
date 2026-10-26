import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_ai_classification_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalSettingsService.resetForTest();
    await LocalSettingsService.init();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SmsAiClassificationCard()),
      ),
    ),
  );

  bool switchValue(WidgetTester tester) => tester
      .widget<Switch>(find.byKey(const ValueKey('sms-ai-consent-switch')))
      .value;

  bool stored() =>
      LocalSettingsService.getBool(smsAiClassificationConsentKey);

  testWidgets('starts off, and "Keep off" leaves it off', (tester) async {
    await pump(tester);
    expect(switchValue(tester), isFalse);

    await tester.tap(find.byKey(const ValueKey('sms-ai-consent-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Let AI help with unclear SMS?'), findsOneWidget);
    expect(find.textContaining('Anthropic'), findsWidgets);

    await tester.tap(find.text('Keep off'));
    await tester.pumpAndSettle();
    expect(switchValue(tester), isFalse);
    expect(stored(), isFalse);
  });

  testWidgets('turns on only after informed consent, and withdraws at once', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('sms-ai-consent-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on AI'));
    await tester.pumpAndSettle();
    expect(switchValue(tester), isTrue);
    expect(stored(), isTrue);

    await tester.tap(find.byKey(const ValueKey('sms-ai-consent-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Let AI help with unclear SMS?'), findsNothing);
    expect(switchValue(tester), isFalse);
    expect(stored(), isFalse);
  });
}
