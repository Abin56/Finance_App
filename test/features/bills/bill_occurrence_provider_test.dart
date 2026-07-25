import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_occurrence_providers.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `materializeBillOccurrenceProvider`/`currentBillOccurrenceProvider`/
/// `billOccurrenceCycleViewProvider` against a real `ProviderContainer` —
/// the full lazy materialize/adopt/rollover flow exercised through the same
/// path the app actually takes (repository -> provider -> screen), mirroring
/// `statement_cycle_view_provider_test.dart`'s structure for Credit Cards.
///
/// Due dates are placed relative to the real, fixed `billCycleAnchor` (day
/// 17) boundary rather than hand-approximated, so this test is correct
/// regardless of what day it happens to run on.
void main() {
  late ProviderContainer container;
  late DateTime closedPeriodDueDate;
  late DateTime currentPeriodDueDate;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    final currentPeriod = billCycleAnchor.currentCycleFor();
    final previousPeriod = billCycleAnchor.previousCycleFor();
    // A due date safely inside each window (the anchor's own boundary day
    // is exclusive-of-previous/inclusive-of-current, so nudge a day in from
    // each window's start to avoid off-by-one ambiguity at the edge).
    currentPeriodDueDate = currentPeriod.start.add(const Duration(days: 1));
    closedPeriodDueDate = previousPeriod.start.add(const Duration(days: 1));
  });

  Future<String> createBill({required DateTime nextDueDate, BillRecurrence recurrence = BillRecurrence.oneTime}) async {
    final bills = container.read(billRepositoryProvider);
    final bill = await bills.createBill(
      name: 'Electricity',
      amount: 1000,
      dueDate: nextDueDate,
      recurrence: recurrence,
    );
    await container.read(billsStreamProvider.future);
    return bill.id;
  }

  /// Awaits [materializeBillOccurrenceProvider] for [billId] — `.listen(...)`
  /// keeps this `autoDispose` family instance alive for the duration of the
  /// await (a bare `ref.read(...future)` with no active listener can be
  /// torn down by autoDispose mid-flight before the Future resolves).
  Future<void> materialize(String billId) async {
    final sub = container.listen(materializeBillOccurrenceProvider(billId), (_, _) {});
    addTearDown(sub.close);
    await container.read(materializeBillOccurrenceProvider(billId).future);
  }

  test('a brand-new bill materializes exactly one current occurrence', () async {
    final billId = await createBill(nextDueDate: currentPeriodDueDate);

    await materialize(billId);
    final occurrence = container.read(currentBillOccurrenceProvider(billId));

    expect(occurrence, isNotNull);
    expect(occurrence!.dueDate, currentPeriodDueDate);
    expect(occurrence.amountPaid, 0);
  });

  test('materializing twice does not create a second occurrence', () async {
    final billId = await createBill(nextDueDate: currentPeriodDueDate);

    await materialize(billId);
    final occurrences = container.read(billOccurrencesStreamProvider(billId)).value;
    await materialize(billId);
    final occurrencesAfterSecondCall = container.read(billOccurrencesStreamProvider(billId)).value;

    expect(occurrencesAfterSecondCall, hasLength(occurrences!.length));
    expect(occurrencesAfterSecondCall, hasLength(1));
  });

  test('an unpaid occurrence due before the current cycle carries forward as pending', () async {
    final billId = await createBill(nextDueDate: closedPeriodDueDate);
    await materialize(billId);

    final view = container.read(billOccurrenceCycleViewProvider(billId));

    expect(view.previousCyclePending, hasLength(1));
    expect(view.previousCyclePending.single.dueDate, closedPeriodDueDate);
  });

  test('a fully paid occurrence due before the current cycle does not carry forward', () async {
    final billId = await createBill(nextDueDate: closedPeriodDueDate);
    await materialize(billId);
    final occurrence = container.read(currentBillOccurrenceProvider(billId))!;

    final occurrenceRepo = container.read(billOccurrenceRepositoryProvider(billId));
    await occurrenceRepo.markPaid(occurrence);
    await container.read(billOccurrencesStreamProvider(billId).future);

    final view = container.read(billOccurrenceCycleViewProvider(billId));
    expect(view.previousCyclePending, isEmpty);
  });

  test('current reflects a not-yet-due occurrence in the live cycle', () async {
    final billId = await createBill(nextDueDate: currentPeriodDueDate);
    await materialize(billId);

    final view = container.read(billOccurrenceCycleViewProvider(billId));

    expect(view.current, isNotNull);
    expect(view.current!.dueDate, currentPeriodDueDate);
  });
}
