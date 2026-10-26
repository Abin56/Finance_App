import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/category_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_ai_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_extractor.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_category_suggester.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser_registry.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the Cloud Function provider: every call here would have
/// been a `classifyFinancialSms` request (and so an Anthropic request).
class _CountingAiProvider implements FinancialEventAiProvider {
  int callCount = 0;

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async {
    callCount++;
    return null;
  }
}

void main() {
  const resolvedAccount = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    matchReason: 'Matched by last-4.',
  );
  final categories = [
    Category(
      id: 'cat-food',
      name: 'Food & Dining',
      type: CategoryType.expense,
      iconKey: 'shopping',
      colorValue: 0xFF000000,
      createdAt: DateTime(2026),
    ),
  ];
  final categoryResolver = CategoryResolver(
    const MerchantCategorySuggester([]),
  );

  // Both messages make AiCallNecessity say "call AI" (see
  // financial_event_extractor_ai_selectivity_test.dart), so any count of zero
  // below comes from the consent gate, not from selectivity.
  const ambiguousBodies = [
    'Rs.500 paid to 9876543210@oksbi via UPI.',
    'Rs.500 debited from a/c XX1234 to ABC Store.',
  ];

  SmsInboxItem buildItem(String body, int n) {
    final message = RawSmsMessage(
      address: 'VM-HDFCBK',
      body: body,
      date: DateTime(2026, 7, 15, 10),
    );
    return SmsInboxItem(
      id: 'sms-$n',
      messageKey: 'key-$n',
      rawMessage: message,
      dedupKey: 'dedup-$n',
      status: SmsImportStatus.pending,
      createdAt: DateTime(2026, 7, 15),
      parsed: SmsFinancialFilter.isFinancial(message)
          ? const SmsParserRegistry().tryParse(message)
          : null,
    );
  }

  Future<void> extractAll(FinancialEventExtractor extractor) async {
    for (final (i, body) in ambiguousBodies.indexed) {
      final item = buildItem(body, i);
      expect(item.parsed, isNotNull);
      final event = await extractor.extract(
        item: item,
        accountMatch: resolvedAccount,
        categories: categories,
      );
      expect(event.amount.value, 500, reason: 'on-device parsing continues');
    }
  }

  group('ConsentGatedFinancialEventAiProvider', () {
    test('AI OFF: zero cloud classification requests', () async {
      final cloud = _CountingAiProvider();
      final extractor = FinancialEventExtractor(
        aiProvider: ConsentGatedFinancialEventAiProvider(
          cloud,
          isAllowed: () => false,
        ),
        categoryResolver: categoryResolver,
      );

      await extractAll(extractor);

      expect(cloud.callCount, 0);
    });

    test('AI ON: requests are forwarded', () async {
      final cloud = _CountingAiProvider();
      final extractor = FinancialEventExtractor(
        aiProvider: ConsentGatedFinancialEventAiProvider(
          cloud,
          isAllowed: () => true,
        ),
        categoryResolver: categoryResolver,
      );

      await extractAll(extractor);

      expect(cloud.callCount, ambiguousBodies.length);
    });

    test('a failing consent read fails closed', () async {
      final cloud = _CountingAiProvider();
      final gate = ConsentGatedFinancialEventAiProvider(
        cloud,
        isAllowed: () => throw StateError('prefs not ready'),
      );
      final extractor = FinancialEventExtractor(
        aiProvider: gate,
        categoryResolver: categoryResolver,
      );

      await extractAll(extractor);

      expect(cloud.callCount, 0);
    });

    test('withdrawal mid-scan stops the very next request', () async {
      final cloud = _CountingAiProvider();
      var allowed = true;
      final extractor = FinancialEventExtractor(
        aiProvider: ConsentGatedFinancialEventAiProvider(
          cloud,
          isAllowed: () => allowed,
        ),
        categoryResolver: categoryResolver,
      );

      await extractor.extract(
        item: buildItem(ambiguousBodies[0], 0),
        accountMatch: resolvedAccount,
        categories: categories,
      );
      expect(cloud.callCount, 1);

      allowed = false;
      await extractor.extract(
        item: buildItem(ambiguousBodies[1], 1),
        accountMatch: resolvedAccount,
        categories: categories,
      );
      expect(cloud.callCount, 1);
    });
  });

  group('stored AI consent', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      LocalSettingsService.resetForTest();
      await LocalSettingsService.init();
    });

    test('an install with no stored consent (older app) means no AI', () {
      expect(readSmsAiClassificationConsent(), isFalse);
    });

    test('unreadable settings mean no AI', () {
      LocalSettingsService.resetForTest();
      expect(readSmsAiClassificationConsent(), isFalse);
    });

    test('grant persists, withdraw persists, and the gate follows', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cloud = _CountingAiProvider();
      final gate = ConsentGatedFinancialEventAiProvider(
        cloud,
        isAllowed: readSmsAiClassificationConsent,
      );
      final notifier = container.read(
        smsAiClassificationConsentProvider.notifier,
      );
      final extractor = FinancialEventExtractor(
        aiProvider: gate,
        categoryResolver: categoryResolver,
      );

      expect(container.read(smsAiClassificationConsentProvider), isFalse);
      await extractAll(extractor);
      expect(cloud.callCount, 0);

      await notifier.grant();
      expect(container.read(smsAiClassificationConsentProvider), isTrue);
      expect(
        LocalSettingsService.getBool(smsAiClassificationConsentKey),
        isTrue,
      );
      await extractAll(extractor);
      expect(cloud.callCount, ambiguousBodies.length);

      await notifier.withdraw();
      expect(container.read(smsAiClassificationConsentProvider), isFalse);
      expect(
        LocalSettingsService.getBool(smsAiClassificationConsentKey),
        isFalse,
      );
      await extractAll(extractor);
      expect(cloud.callCount, ambiguousBodies.length);
    });
  });
}
