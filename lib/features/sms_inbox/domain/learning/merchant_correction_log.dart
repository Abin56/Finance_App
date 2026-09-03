import 'correction_event.dart';
import 'learned_field.dart';

/// An append-only history of `CorrectionEvent`s. Pure in-memory bookkeeping —
/// persistence, if this is ever wired into `sms_inbox.db`, belongs in a DAO
/// the same shape as `MerchantMemoryDao`, not here. Deliberately append-only:
/// nothing in this layer ever deletes or overwrites a past correction, so a
/// merchant's full history is always reconstructable (requirement this
/// module's conflict resolution depends on — see `MerchantPreferenceResolver`).
class MerchantCorrectionLog {
  MerchantCorrectionLog([List<CorrectionEvent>? seed])
    : _events = List.of(seed ?? const <CorrectionEvent>[]);

  final List<CorrectionEvent> _events;

  List<CorrectionEvent> get all => List.unmodifiable(_events);

  void record(CorrectionEvent event) => _events.add(event);

  List<CorrectionEvent> forMerchant(String merchantKey) =>
      _events.where((e) => e.merchantKey == merchantKey).toList();

  List<CorrectionEvent> forField(String merchantKey, LearnedFieldType field) =>
      forMerchant(
        merchantKey,
      ).where((e) => e.field == field).toList();

  List<CorrectionEvent> since(
    String merchantKey,
    LearnedFieldType field,
    DateTime cutoff,
  ) => forField(
    merchantKey,
    field,
  ).where((e) => e.timestamp.isAfter(cutoff)).toList();
}
