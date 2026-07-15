import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_bulk_converter.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_bulk_convert_sheet.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_memory.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';

/// Stands in for the on-device merchant-memory store, which otherwise needs a
/// real sqflite database. Empty, so these tests exercise the seed-catalog
/// suggestion path rather than a learned one.
class _StubMemoriesNotifier extends MerchantMemoriesNotifier {
  @override
  Future<List<MerchantMemory>> build() async => const [];
}

/// The bulk sheet is the one place a wrong shared answer would be applied to
/// many real transactions at once, so these pin the guardrails that keep it
/// honest — plus the small-Android layout budget every FlowFi sheet is held
/// to.
void main() {
  Category category(String id, String name, CategoryType type) => Category(
        id: id,
        name: name,
        type: type,
        iconKey: 'shopping',
        colorValue: 0xFF000000,
        createdAt: DateTime(2026),
      );

  final categories = [
    category('cat-food', 'Food & Dining', CategoryType.expense),
    category('cat-shopping', 'Shopping', CategoryType.expense),
    category('cat-salary', 'Salary', CategoryType.income),
  ];

  final accounts = [
    Account(
      id: 'acc-1',
      name: 'HDFC Savings',
      type: AccountType.bank,
      openingBalance: 0,
      currentBalance: 0,
      colorValue: 0xFF000000,
      createdAt: DateTime(2026),
    ),
  ];

  SmsInboxItem item({
    required String id,
    double? amount = 100,
    String merchant = 'Amazon',
    SmsTransactionDirection direction = SmsTransactionDirection.debit,
  }) {
    final date = DateTime(2026, 7, 15, 12);
    return SmsInboxItem(
      id: id,
      messageKey: 'msg-$id',
      rawMessage: RawSmsMessage(address: 'VM-HDFCBK', body: 'body $id', date: date),
      dedupKey: 'dedup-$id',
      status: SmsImportStatus.pending,
      createdAt: date,
      parsed: amount == null
          ? null
          : ParsedSmsTransaction(
              amount: amount,
              direction: direction,
              dateTime: date,
              category: SmsTransactionCategory.cardPurchase,
              confidence: 0.9,
              rawBody: 'body $id',
              merchantOrSender: merchant,
            ),
    );
  }

  Future<SmsBulkConvertConfig?> pumpSheet(
    WidgetTester tester,
    List<SmsInboxItem> items, {
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SmsBulkConvertConfig? config;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
          accountsStreamProvider.overrideWith((ref) => Stream.value(accounts)),
          merchantMemoriesProvider.overrideWith(_StubMemoriesNotifier.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => config = await SmsBulkConvertSheet.show(context, items),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return config;
  }

  testWidgets('says how many messages and that each becomes its own transaction', (tester) async {
    await pumpSheet(tester, [item(id: 'a'), item(id: 'b')]);

    expect(find.text('Convert 2 messages'), findsOneWidget);
    expect(find.textContaining('Each message becomes its own transaction'), findsOneWidget);
    expect(find.text('Create 2 transactions'), findsOneWidget);
  });

  testWidgets('counts in grammatical singular for one message', (tester) async {
    await pumpSheet(tester, [item(id: 'a')]);

    expect(find.text('Convert 1 message'), findsOneWidget);
    expect(find.text('Create 1 transaction'), findsOneWidget);
  });

  testWidgets('defaults to Income when most of the selection is money coming in', (tester) async {
    // The "10 salary SMS" case should open on the right side of the ledger.
    await pumpSheet(tester, [
      item(id: 'a', direction: SmsTransactionDirection.credit),
      item(id: 'b', direction: SmsTransactionDirection.credit),
    ]);

    final segmented = tester.widget<SegmentedButton<TransactionType>>(find.byType(SegmentedButton<TransactionType>));
    expect(segmented.selected, {TransactionType.income});
  });

  testWidgets('suggests a category when every message is from the same merchant', (tester) async {
    // The "15 Amazon purchases" case — one suggestion is right for all of
    // them, so it should already be filled in.
    await pumpSheet(tester, [item(id: 'a'), item(id: 'b')]);

    expect(find.text('Shopping'), findsOneWidget);
  });

  testWidgets('suggests nothing when the selection spans different merchants', (tester) async {
    // Any single category would be wrong for most of a mixed selection.
    await pumpSheet(tester, [item(id: 'a', merchant: 'Amazon'), item(id: 'b', merchant: 'Swiggy')]);

    expect(find.text('Select a category'), findsOneWidget);
  });

  testWidgets('warns when the chosen type contradicts some of the selection', (tester) async {
    await pumpSheet(tester, [
      item(id: 'a', direction: SmsTransactionDirection.debit),
      item(id: 'b', direction: SmsTransactionDirection.debit),
      item(id: 'c', direction: SmsTransactionDirection.credit),
    ]);

    expect(find.textContaining('look like money coming in'), findsOneWidget);
  });

  testWidgets('warns up front about messages with no readable amount', (tester) async {
    await pumpSheet(tester, [item(id: 'a'), item(id: 'b', amount: null)]);

    expect(find.textContaining('have no readable amount and will be'), findsOneWidget);
    // The button promises only what can actually be created.
    expect(find.text('Create 1 transaction'), findsOneWidget);
  });

  testWidgets('will not return a config without a payment method chosen', (tester) async {
    // Category is pre-suggested here, so payment method is the missing one —
    // it must block rather than silently pick an account.
    final config = await pumpSheet(tester, [item(id: 'a'), item(id: 'b')]);
    await tester.tap(find.text('Create 2 transactions'));
    await tester.pumpAndSettle();

    expect(config, isNull);
    expect(find.text('Select a payment method'), findsWidgets);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('does not overflow at ${width.toInt()}dp with both warnings showing', (tester) async {
      await pumpSheet(
        tester,
        [
          item(id: 'a', merchant: 'A very long merchant name from the bank feed'),
          item(id: 'b', direction: SmsTransactionDirection.credit, merchant: 'Another long merchant name'),
          item(id: 'c', amount: null),
        ],
        width: width,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
