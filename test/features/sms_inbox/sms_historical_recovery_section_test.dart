import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_historical_recovery.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_historical_recovery_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeItems extends SmsInboxItemsNotifier {
  _FakeItems(this.items);

  final List<SmsInboxItem> items;

  @override
  Future<List<SmsInboxItem>> build() async => items;

  @override
  Future<void> refresh() async => state = AsyncData(List.of(items));
}

class _FakeRecovery implements SmsHistoricalRecovery {
  _FakeRecovery(this.result, this.items);

  final SmsHistoricalRecoveryResult result;
  final List<SmsInboxItem> items;
  final runs = <String>[];

  /// Mimics the real claim: unowned rows become owned by [confirmedUid].
  @override
  Future<SmsHistoricalRecoveryResult> run(String confirmedUid) async {
    runs.add(confirmedUid);
    for (var i = 0; i < items.length; i++) {
      if (items[i].capturedForUid == null) {
        items[i] = _item(items[i].id, owner: confirmedUid);
      }
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SmsInboxItem _item(String id, {String? owner}) => SmsInboxItem(
  id: id,
  messageKey: 'mk-$id',
  rawMessage: RawSmsMessage(
    address: 'VM-HDFCBK',
    body: 'Rs.10 debited',
    date: DateTime(2026, 7, 1),
  ),
  dedupKey: 'dk-$id',
  status: SmsImportStatus.pending,
  createdAt: DateTime(2026, 7, 1),
  capturedForUid: owner,
);

TransactionCandidate _candidate(String smsId) => TransactionCandidate(
  id: 'cand-$smsId',
  smsItemId: smsId,
  amount: 10,
  direction: SmsTransactionDirection.debit,
  eventType: SmsTransactionCategory.values.first,
  transactionDate: DateTime(2026, 7, 1),
  confidenceLevel: ConfidenceLevel.low,
  confidenceScore: 0.2,
  needsReview: true,
  createdAt: DateTime(2026, 7, 1),
);

Future<_FakeRecovery> _pump(
  WidgetTester tester, {
  required List<SmsInboxItem> items,
  SmsHistoricalRecoveryResult result = const SmsHistoricalRecoveryResult(
    outcome: SmsRecoveryOutcome.completed,
    linked: 2,
    uploaded: 2,
  ),
  String? uid = 'uid-a',
}) async {
  final recovery = _FakeRecovery(result, items);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        smsInboxItemsProvider.overrideWith(() => _FakeItems(items)),
        transactionCandidatesProvider.overrideWith(
          (ref) async => [for (final i in items) _candidate(i.id)],
        ),
        smsHistoricalRecoveryProvider.overrideWithValue(recovery),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SmsHistoricalRecoverySection(uidResolver: () => uid),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return recovery;
}

void main() {
  late List<SmsInboxItem> items;
  setUp(() {
    items = [_item('a'), _item('b'), _item('c', owner: 'uid-other')];
  });

  testWidgets('shows only the unowned eligible count', (tester) async {
    await _pump(tester, items: items);
    expect(find.text('Earlier messages: 2'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final recovery = await _pump(tester, items: items);
    await tester.tap(find.text('Link to this account and upload'));
    await tester.pumpAndSettle();
    expect(find.text('Link earlier messages?'), findsOneWidget);
    expect(find.textContaining('not changed'), findsOneWidget);
    expect(find.textContaining('no transactions are created'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(recovery.runs, isEmpty);
  });

  testWidgets('confirming runs recovery for the signed-in uid and shows real counts', (
    tester,
  ) async {
    final recovery = await _pump(tester, items: items);
    await tester.tap(find.text('Link to this account and upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link and upload'));
    await tester.pumpAndSettle();

    expect(recovery.runs, ['uid-a']);
    expect(
      find.textContaining('Uploaded 2 candidates'),
      findsOneWidget,
    );
  });

  testWidgets('offline result offers Retry upload without re-confirming', (
    tester,
  ) async {
    final recovery = await _pump(
      tester,
      items: items,
      result: const SmsHistoricalRecoveryResult(
        outcome: SmsRecoveryOutcome.offline,
        linked: 2,
      ),
    );
    await tester.tap(find.text('Link to this account and upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link and upload'));
    await tester.pumpAndSettle();

    expect(find.textContaining('nothing was uploaded'), findsOneWidget);
    expect(find.textContaining('Uploaded'), findsNothing);
    expect(find.text('Link to this account and upload'), findsNothing);

    await tester.tap(find.text('Retry upload'));
    await tester.pumpAndSettle();
    expect(find.text('Link earlier messages?'), findsNothing);
    expect(recovery.runs, ['uid-a', 'uid-a']);
  });

  testWidgets('hidden when nothing is eligible', (tester) async {
    await _pump(tester, items: [_item('c', owner: 'uid-other')]);
    expect(find.text('Link to this account and upload'), findsNothing);
  });

  testWidgets('hidden when signed out', (tester) async {
    await _pump(tester, items: items, uid: null);
    expect(find.textContaining('Earlier messages'), findsNothing);
  });
}
