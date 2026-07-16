import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/sms_inbox/domain/filter/sms_filter_criteria.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_filter_sheet.dart';

/// The reported Android widths. The sheet must lay out without overflow on
/// each — the narrowest is where the chip rows and the header badge bite.
const _widths = <double>[360, 390, 412];

/// Stands in for the sqflite-backed notifier so the sheet's derived option
/// lists (banks, categories) have data without touching a database.
class _FakeItems extends SmsInboxItemsNotifier {
  _FakeItems(this._items);

  final List<SmsInboxItem> _items;

  @override
  Future<List<SmsInboxItem>> build() async => _items;
}

SmsInboxItem _item(String id, {String? bank, String? lastFour}) {
  final when = DateTime(2026, 3, 10);
  return SmsInboxItem(
    id: id,
    messageKey: 'msg-$id',
    rawMessage: RawSmsMessage(address: 'VM-BANK', body: 'body', date: when),
    dedupKey: id,
    status: SmsImportStatus.pending,
    createdAt: when,
    parsed: ParsedSmsTransaction(
      amount: 250,
      direction: SmsTransactionDirection.debit,
      dateTime: when,
      category: SmsTransactionCategory.upiPayment,
      confidence: 0.9,
      rawBody: 'body',
      bankName: bank,
      maskedAccountOrCard: lastFour,
    ),
  );
}

void main() {
  late ProviderContainer container;

  Widget harness() {
    final account = Account(
      id: 'acc-1',
      name: 'HDFC Millennia',
      type: AccountType.card,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF000000,
      createdAt: DateTime(2026),
    );
    final card = CreditCardProfile(
      id: 'card-1',
      accountId: 'acc-1',
      statementDay: 5,
      paymentDueDay: 25,
      creditLimit: 100000,
      createdAt: DateTime(2026),
      lastFourDigits: '4589',
    );

    container = ProviderContainer(
      overrides: [
        smsInboxItemsProvider.overrideWith(
          () => _FakeItems([_item('a', bank: 'SBI'), _item('b', bank: 'HDFC', lastFour: '4589')]),
        ),
        accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
        creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
      ],
    );
    addTearDown(container.dispose);

    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SmsFilterSheet.show(context),
              child: const Text('open filters'),
            ),
          ),
        ),
      ),
    );
  }

  for (final width in _widths) {
    group('at ${width.toInt()}dp', () {
      testWidgets('sheet lays out every section without overflow', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open filters'));
        await tester.pumpAndSettle();

        expect(find.text('Filter SMS'), findsOneWidget);
        expect(find.text('Money direction'), findsOneWidget);
        expect(find.text('Clear All'), findsOneWidget);
        expect(find.text('Apply Filters'), findsOneWidget);

        // Banks come from the scanned messages, not a hardcoded list.
        expect(find.text('SBI'), findsOneWidget);
        expect(find.text('HDFC'), findsOneWidget);

        // The Card section sits below the fold, so scroll the sheet's own
        // list to it. Card options are labelled from the linked account name
        // plus the last-4, matching how CreditCardsScreen names a card.
        final sheetList = find
            .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(find.text('HDFC Millennia •••• 4589'), 200, scrollable: sheetList);
        expect(find.text('HDFC Millennia •••• 4589'), findsOneWidget);
        expect(find.text('Unknown card'), findsOneWidget);
      });

      testWidgets('combining facets applies them all at once', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open filters'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Outgoing money'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SBI'));
        await tester.pumpAndSettle();

        // Nothing lands until Apply, so a half-built filter never churns the
        // feed under the sheet.
        expect(container.read(smsFilterCriteriaProvider).hasActiveFilters, isFalse);

        await tester.tap(find.text('Apply Filters'));
        await tester.pumpAndSettle();

        final applied = container.read(smsFilterCriteriaProvider);
        expect(applied.direction, SmsMoneyDirection.outgoing);
        expect(applied.banks, {'SBI'});
        expect(applied.activeCount, 2);
      });

      testWidgets('an invalid Min/Max range shows an error and Apply does not take effect', (tester) async {
        // Regression: Min/Max amount fields weren't cross-validated, so a
        // range that can never match anything (Min > Max) silently applied
        // with no explanation.
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open filters'));
        await tester.pumpAndSettle();

        final minField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Min');
        final maxField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Max');
        final sheetList = find
            .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(minField, 200, scrollable: sheetList);

        await tester.enterText(minField, '5000');
        await tester.pumpAndSettle();
        await tester.enterText(maxField, '100');
        await tester.pumpAndSettle();

        expect(find.text('Min must not be greater than Max.'), findsOneWidget);

        await tester.tap(find.text('Apply Filters'));
        await tester.pumpAndSettle();

        expect(container.read(smsFilterCriteriaProvider).hasActiveFilters, isFalse);
      });

      testWidgets('closing without applying discards the draft', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open filters'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Outgoing money'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();

        expect(container.read(smsFilterCriteriaProvider).hasActiveFilters, isFalse);
      });
    });
  }
}
