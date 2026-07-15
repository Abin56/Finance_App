import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_message_tile.dart';

/// The SMS Inbox's compact rows are the whole point of the redesign, so they
/// are pinned to the small-Android budget here: they must stay within the
/// 70-90dp band and must not overflow at 360dp, even with worst-case
/// merchant/bank text and a large accessibility text scale.
void main() {
  SmsInboxItem itemWith({
    String merchant = 'Amazon',
    String bank = 'SBI',
    SmsTransactionDirection direction = SmsTransactionDirection.debit,
    SmsImportStatus status = SmsImportStatus.pending,
    bool parsed = true,
  }) {
    final date = DateTime(2026, 7, 15, 16, 35);
    return SmsInboxItem(
      id: 'id-$merchant-$status',
      messageKey: 'msg-$merchant-$status',
      rawMessage: RawSmsMessage(address: 'VM-SBIBNK', body: 'Rs.1250 debited', date: date),
      dedupKey: 'key-$merchant',
      status: status,
      createdAt: date,
      parsed: parsed
          ? ParsedSmsTransaction(
              amount: 1250,
              direction: direction,
              dateTime: date,
              category: SmsTransactionCategory.cardPurchase,
              confidence: 0.9,
              rawBody: 'Rs.1250 debited',
              merchantOrSender: merchant,
              bankName: bank,
              maskedAccountOrCard: '1234',
            )
          : null,
    );
  }

  Future<void> pumpTile(
    WidgetTester tester,
    SmsInboxItem item, {
    double width = 360,
    double textScale = 1.0,
    bool selectionMode = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          home: Scaffold(
            body: SmsMessageTile(item: item, onTap: () {}, selectionMode: selectionMode),
          ),
        ),
      ),
    );
  }

  group('compact row height', () {
    testWidgets('stays inside the 70-90dp band at 360dp', (tester) async {
      await pumpTile(tester, itemWith());

      final height = tester.getSize(find.byType(SmsMessageTile)).height;
      expect(height, greaterThanOrEqualTo(70));
      expect(height, lessThanOrEqualTo(90));
    });

    testWidgets('does not change between normal and selection mode', (tester) async {
      await pumpTile(tester, itemWith());
      final normal = tester.getSize(find.byType(SmsMessageTile)).height;

      await pumpTile(tester, itemWith(), selectionMode: true);
      expect(tester.getSize(find.byType(SmsMessageTile)).height, normal);
    });
  });

  group('no overflow', () {
    for (final width in [360.0, 390.0, 412.0]) {
      testWidgets('renders a long merchant + bank at ${width.toInt()}dp', (tester) async {
        await pumpTile(
          tester,
          itemWith(
            merchant: 'SWIGGY INSTAMART BENGALURU KARNATAKA IN',
            bank: 'KOTAK MAHINDRA BANK LIMITED',
          ),
          width: width,
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('survives a 1.3x accessibility text scale', (tester) async {
      await pumpTile(tester, itemWith(), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  group('content', () {
    testWidgets('labels a debit as spent and a credit as received', (tester) async {
      await pumpTile(tester, itemWith());
      expect(find.textContaining('spent'), findsOneWidget);

      await pumpTile(tester, itemWith(direction: SmsTransactionDirection.credit));
      expect(find.textContaining('received'), findsOneWidget);
    });

    testWidgets('shows a short status chip per import status', (tester) async {
      await pumpTile(tester, itemWith(status: SmsImportStatus.pending));
      expect(find.text('Pending'), findsOneWidget);

      await pumpTile(tester, itemWith(status: SmsImportStatus.imported));
      expect(find.text('Converted'), findsOneWidget);

      await pumpTile(tester, itemWith(status: SmsImportStatus.ignored));
      expect(find.text('Ignored'), findsOneWidget);
    });

    testWidgets('falls back to the sender when nothing could be parsed', (tester) async {
      await pumpTile(tester, itemWith(parsed: false));

      expect(find.text('Amount unclear'), findsOneWidget);
      expect(find.textContaining('VM-SBIBNK'), findsOneWidget);
    });
  });
}
