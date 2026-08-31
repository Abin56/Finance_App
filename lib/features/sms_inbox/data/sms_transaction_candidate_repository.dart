import '../../../core/data/firestore_crud_repository.dart';
import '../domain/sms_transaction_candidate_cloud.dart';

/// Cloud persistence for `SmsTransactionCandidateCloud` — plain CRUD on top
/// of the shared [FirestoreCrudRepository], same architecture as
/// `AccountRepository`/`TransactionRepository`. No candidate-specific
/// business logic lives here; that's [SmsCandidateCloudSync]'s job, exactly
/// how `SmsBulkConverter` stays a thin loop over `TransactionRepository`
/// rather than folding its own logic into the repository.
///
/// Adds exactly one operation beyond the base class: [deleteById]. Every
/// other base method already works unmodified because
/// [SmsTransactionCandidateCloud.id] is stable (the source `SmsInboxItem.id`),
/// so [add]/[permanentlyDelete] already target the right document via
/// `entity.id` — [deleteById] exists only for the (common) case where the
/// caller has an id from the cloud side and no in-memory entity to hand back.
class SmsTransactionCandidateRepository extends FirestoreCrudRepository<SmsTransactionCandidateCloud> {
  SmsTransactionCandidateRepository(super.collection);

  Future<void> deleteById(String id) => collection.doc(id).delete();
}
