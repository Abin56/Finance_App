import 'financial_obligation.dart';
import 'obligation_link.dart';

/// The read-only query surface [ObligationLinker] needs — kept as an
/// interface (rather than depending on a concrete repository/DAO directly)
/// so Phase 5's richer transaction-linking engine can supply a smarter
/// implementation later without this class changing. See Part 5's explicit
/// ask for "a safe interface and conservative deterministic implementation"
/// now, with room for a fuzzier matcher later.
abstract class ObligationLookup {
  /// Outstanding obligations (see `ObligationStatus.isOutstanding`) whose
  /// merchant/provider text overlaps [merchantOrSender] and whose due date
  /// falls within a reasonable window of [anchorDate] — a loose prefilter;
  /// [ObligationLinker] does the actual amount/reference matching.
  Future<List<FinancialObligation>> findOutstandingByMerchant({
    required String? merchantOrSender,
    required DateTime anchorDate,
    required Duration lookback,
  });

  /// An outstanding obligation with this exact reference/UTR number, if
  /// any.
  Future<FinancialObligation?> findOutstandingByReferenceNumber(
    String referenceNumber,
  );
}

/// Decides whether a newly-observed completed [FinancialEvent] resolves an
/// existing outstanding [FinancialObligation] — the Part 5 "obligation
/// linking foundation." Deliberately conservative and deterministic, the
/// same posture `TransactionMatcher` already takes for event-to-event
/// linking: reference number is the strongest signal (checked first);
/// sender/merchant + amount within a lookback window is the fallback, and
/// an ambiguous multi-candidate match is always surfaced for manual
/// confirmation rather than silently picked.
///
/// This never mutates a [FinancialEvent] or marks anything paid on its
/// own — it only returns a verdict. The caller (a future integration point,
/// not built in this phase) decides whether/how to apply it, matching this
/// engine's "never auto-execute" posture (see Safety rule 10 and
/// `AutomationAction`'s doc comment on the FinancialEvent side).
class ObligationLinker {
  const ObligationLinker(this._lookup);

  final ObligationLookup _lookup;

  /// How far back an outstanding obligation is allowed to have been
  /// detected/due and still be considered resolved by a later payment —
  /// wide enough for "EMI due in 5 days" followed by a payment a week
  /// later, narrow enough not to match unrelated history.
  static const defaultLookback = Duration(days: 60);

  Future<ObligationLinkOutcome> link({
    required double? amount,
    required String? merchantOrSender,
    required DateTime completedAt,
    String? referenceNumber,
    Duration lookback = defaultLookback,
  }) async {
    if (referenceNumber != null && referenceNumber.isNotEmpty) {
      final byReference = await _lookup.findOutstandingByReferenceNumber(
        referenceNumber,
      );
      if (byReference != null) {
        return ObligationLinkOutcome(
          result: ObligationLinkResult.linkedResolved,
          matchedObligationId: byReference.id,
          confidence: 0.95,
          reason:
              'Same reference number ($referenceNumber) as an outstanding obligation.',
        );
      }
    }

    if (amount == null ||
        merchantOrSender == null ||
        merchantOrSender.isEmpty) {
      return const ObligationLinkOutcome(
        result: ObligationLinkResult.noMatch,
        confidence: 0.0,
        reason:
            'Not enough signal (amount and/or merchant) to match against an outstanding obligation.',
      );
    }

    final candidates = await _lookup.findOutstandingByMerchant(
      merchantOrSender: merchantOrSender,
      anchorDate: completedAt,
      lookback: lookback,
    );

    final amountMatches = candidates
        .where(
          (o) =>
              o.amount.value != null && (o.amount.value! - amount).abs() < 0.01,
        )
        .toList();

    if (amountMatches.isEmpty) {
      return const ObligationLinkOutcome(
        result: ObligationLinkResult.noMatch,
        confidence: 0.0,
        reason:
            'No outstanding obligation with a matching merchant and amount was found.',
      );
    }

    if (amountMatches.length == 1) {
      return ObligationLinkOutcome(
        result: ObligationLinkResult.linkedResolved,
        matchedObligationId: amountMatches.first.id,
        confidence: 0.75,
        reason:
            'Same merchant and amount as an outstanding obligation, within the lookback window.',
      );
    }

    return ObligationLinkOutcome(
      result: ObligationLinkResult.possibleMatch,
      matchedObligationId: amountMatches.first.id,
      confidence: 0.4,
      reason:
          'Multiple outstanding obligations share this merchant and amount — surfaced for manual confirmation rather than auto-resolved.',
    );
  }
}
