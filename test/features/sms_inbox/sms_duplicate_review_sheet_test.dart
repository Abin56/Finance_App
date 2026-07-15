import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_duplicate_reason.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_duplicate_review_sheet.dart';

class _StubItemsNotifier extends SmsInboxItemsNotifier {
  _StubItemsNotifier(this._items);

  final List<SmsInboxItem> _items;

  @override
  Future<List<SmsInboxItem>> build() async => _items;
}

/// The review sheet has to justify a judgement the app made about the user's
/// own data, so these pin the two things that makes it honest: the detection
/// reason and both messages are actually on screen, and the sheet survives a
/// long bank body at 360dp without overflowing.
void main() {
  SmsInboxItem item({required String id, String? duplicateOf, String body = 'Rs.1250 debited'}) {
    final date = DateTime(2026, 7, 15, 16, 35);
    return SmsInboxItem(
      id: id,
      messageKey: 'msg-$id',
      rawMessage: RawSmsMessage(address: 'VM-HDFCBK', body: body, date: date),
      dedupKey: 'dedup',
      duplicateOfId: duplicateOf,
      duplicateReason: duplicateOf == null ? null : SmsDuplicateReason.sameReferenceNumber,
      status: SmsImportStatus.pending,
      createdAt: date,
      parsed: ParsedSmsTransaction(
        amount: 1250,
        direction: SmsTransactionDirection.debit,
        dateTime: date,
        category: SmsTransactionCategory.upiPayment,
        confidence: 0.9,
        rawBody: body,
        merchantOrSender: 'Swiggy',
      ),
    );
  }

  Future<void> pumpSheet(
    WidgetTester tester,
    List<SmsInboxItem> items,
    SmsInboxItem duplicate, {
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsInboxItemsProvider.overrideWith(() => _StubItemsNotifier(items)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SmsDuplicateReviewSheet.show(context, duplicate),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the detection reason and both messages', (tester) async {
    final original = item(id: 'original', body: 'Rs.1250 debited to Swiggy. Ref 12345.');
    final duplicate = item(id: 'copy', duplicateOf: 'original', body: 'Rs.1250 debited to Swiggy. Ref 12345. Offer!');

    await pumpSheet(tester, [original, duplicate], duplicate);

    expect(find.text('Possible duplicate'), findsOneWidget);
    expect(find.text(SmsDuplicateReason.sameReferenceNumber.explanation), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('This message'), findsOneWidget);
  });

  testWidgets('offers every review action, including overruling the app', (tester) async {
    final original = item(id: 'original');
    final duplicate = item(id: 'copy', duplicateOf: 'original');

    await pumpSheet(tester, [original, duplicate], duplicate);

    expect(find.text('Delete duplicate'), findsOneWidget);
    expect(find.text('Move to Inbox'), findsOneWidget);
    expect(find.text('Convert anyway'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
  });

  testWidgets('returns the chosen action to the caller', (tester) async {
    final original = item(id: 'original');
    final duplicate = item(id: 'copy', duplicateOf: 'original');

    SmsDuplicateAction? result;
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsInboxItemsProvider.overrideWith(() => _StubItemsNotifier([original, duplicate])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => result = await SmsDuplicateReviewSheet.show(context, duplicate),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Inbox'));
    await tester.pumpAndSettle();

    expect(result, SmsDuplicateAction.moveToInbox);
  });

  testWidgets('says so when the original has since been deleted', (tester) async {
    // Otherwise the sheet would show a lone message under a "duplicate"
    // heading it can no longer justify.
    final duplicate = item(id: 'copy', duplicateOf: 'gone');

    await pumpSheet(tester, [duplicate], duplicate);

    expect(find.text('The original message has since been deleted.'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('does not overflow at ${width.toInt()}dp with a long bank body', (tester) async {
      final body = 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. '
          'Ref No 123456789012. Not you? Call 18001234567 immediately to report this transaction.';
      final original = item(id: 'original', body: body);
      final duplicate = item(id: 'copy', duplicateOf: 'original', body: '$body Download our app today!');

      await pumpSheet(tester, [original, duplicate], duplicate, width: width);

      expect(tester.takeException(), isNull);
    });
  }
}
