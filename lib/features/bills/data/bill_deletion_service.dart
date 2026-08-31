import 'bill_occurrence_repository.dart';
import 'bill_repository.dart';
import 'payment_repository.dart';
import '../domain/bill.dart';

/// Permanently wipes [bill] and everything under it — `occurrences` and
/// `payments` (both live directly under `bills/{billId}`, per
/// `FirestoreCollections`' doc comments), active and trashed alike, then the
/// `Bill` document itself. Unlike the bare `permanentlyDelete` both
/// `BillsTrashScreen` and the account/credit-card permanent-delete cascade
/// (`account_deletion_service.dart`) used to call, this doesn't leave those
/// subcollections orphaned. A standalone function (not a `BillRepository`
/// method) since `occurrenceRepository`/`paymentRepository` are per-bill
/// (family-scoped) repositories the caller already has from the provider
/// layer — mirrors `PersonRepository.deletePersonAndLedger`'s
/// pass-the-scoped-repo-in shape.
Future<void> permanentlyDeleteBillAndHistory(
  Bill bill, {
  required BillRepository billRepository,
  required BillOccurrenceRepository occurrenceRepository,
  required PaymentRepository paymentRepository,
}) async {
  final occurrences = [...await occurrenceRepository.getAll(), ...await occurrenceRepository.getTrash()];
  for (final occurrence in occurrences) {
    await occurrenceRepository.permanentlyDelete(occurrence);
  }

  final payments = [...await paymentRepository.getAll(), ...await paymentRepository.getTrash()];
  for (final payment in payments) {
    await paymentRepository.permanentlyDelete(payment);
  }

  await billRepository.permanentlyDelete(bill);
}
