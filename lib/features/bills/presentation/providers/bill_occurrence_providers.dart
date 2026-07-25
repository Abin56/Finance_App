import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/payment_schedule/domain/cycle_anchor.dart';
import '../../../../core/payment_schedule/domain/cycle_engine.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../data/bill_occurrence_repository.dart';
import '../../domain/bill_occurrence.dart';
import '../../domain/bill_occurrence_cycle_item.dart';
import '../../domain/bill_status.dart';
import 'bill_providers.dart';

/// The cycle anchor every bill's occurrences classify against — day 17,
/// the same shared constant Credit Cards/People/EMI/Loan already use (see
/// `personCycleAnchor`/`emiCycleAnchor`), so every financial module
/// classifies Previous/Current/Future against one consistent app-wide
/// cycle boundary rather than each choosing its own.
const billCycleAnchor = CycleAnchor(anchorDay: 17);

final billOccurrenceRepositoryProvider = Provider.autoDispose.family<BillOccurrenceRepository, String>((
  ref,
  billId,
) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final billDoc = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.bills)
      .doc(billId);
  final collection = billDoc
      .collection(FirestoreCollections.billOccurrences)
      .withConverter<BillOccurrence>(
        fromFirestore: BillOccurrence.fromFirestore,
        toFirestore: (occurrence, _) => occurrence.toFirestore(),
      );
  return BillOccurrenceRepository(
    collection,
    ref.watch(billRepositoryProvider),
    billDoc,
    billDoc.collection(FirestoreCollections.payments),
  );
});

final billOccurrencesStreamProvider = StreamProvider.autoDispose.family<List<BillOccurrence>, String>((ref, billId) {
  return ref.watch(billOccurrenceRepositoryProvider(billId)).watchAll();
});

/// Side-effect provider — triggers `ensureCurrentOccurrence` (materialize a
/// fresh occurrence, roll one forward, or one-time-adopt a pre-migration
/// bill's in-progress state) whenever a bill's screen is opened. Mirrors
/// `materializeStatementProvider` exactly: screens watch
/// [billOccurrencesStreamProvider]/[currentBillOccurrenceProvider] for the
/// actual data; this provider's return value only matters for surfacing an
/// error, if any.
final materializeBillOccurrenceProvider = FutureProvider.autoDispose.family<void, String>((ref, billId) async {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final bill = bills.where((b) => b.id == billId).firstOrNull;
  if (bill == null) return;
  final existing = ref.watch(billOccurrencesStreamProvider(billId)).value ?? const [];
  final legacyPayments = ref.watch(paymentsStreamProvider(billId)).value ?? const [];
  await ref.watch(billOccurrenceRepositoryProvider(billId)).ensureCurrentOccurrence(
        bill,
        existing,
        legacyPayments: legacyPayments,
      );
});

/// The occurrence every screen treats as "this bill's current standing" —
/// the soonest-due unsettled occurrence, or (rare/momentary) the most
/// recently materialized one if every occurrence loaded so far is settled.
/// Null only if [materializeBillOccurrenceProvider] hasn't run yet for this
/// bill (nothing materialized) — every bill has exactly one such occurrence
/// once that's happened at least once.
final currentBillOccurrenceProvider = Provider.autoDispose.family<BillOccurrence?, String>((ref, billId) {
  final occurrences = ref.watch(billOccurrencesStreamProvider(billId)).value ?? const [];
  if (occurrences.isEmpty) return null;
  final unsettled = occurrences.where((o) => o.status != BillStatus.paid && o.status != BillStatus.skipped);
  if (unsettled.isNotEmpty) {
    return unsettled.reduce((a, b) => a.dueDate.isBefore(b.dueDate) ? a : b);
  }
  return occurrences.reduce((a, b) => a.dueDate.isAfter(b.dueDate) ? a : b);
});

typedef BillOccurrenceCycleView = ({List<BillOccurrence> previousCyclePending, BillOccurrence? current});

/// A single bill's occurrences split into Previous-Cycle-Pending / Current
/// via the shared `CycleEngine` — the same carry-forward rule Credit Cards
/// (`statementCycleViewProvider`), People (`personCycleViewProvider`), and
/// EMI/Loan already use, anchored at the same shared `billCycleAnchor` (day
/// 17) so every financial module classifies against one consistent cycle
/// boundary. Unlike the old `BillCycleItem`-based `billCycleViewProvider`,
/// each occurrence here is its own immutable document, so a genuinely
/// distinct previous occurrence can carry forward instead of reflecting
/// only the current one's rolled-over state.
final billOccurrenceCycleViewProvider = Provider.autoDispose.family<BillOccurrenceCycleView, String>((ref, billId) {
  final occurrences = ref.watch(billOccurrencesStreamProvider(billId)).value ?? const [];
  final items = occurrences.map(BillOccurrenceCycleItem.new).toList();
  final result = CycleEngine.classifyForCarryForward(items, billCycleAnchor);
  final previousCyclePending = result.previousCyclePending.map((item) => item.occurrence).toList();
  return (previousCyclePending: previousCyclePending, current: ref.watch(currentBillOccurrenceProvider(billId)));
});
