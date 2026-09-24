import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/financial_obligation.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_date_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_link.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_linker.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_recurrence.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_source.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_status.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_type.dart';
import 'package:flutter_test/flutter_test.dart';

FinancialObligation _obligation({
  required String id,
  required String merchant,
  required double amount,
  DateTime? dueDate,
  String? referenceNumber,
  ObligationStatus status = ObligationStatus.due,
}) {
  final now = DateTime(2026, 9, 1);
  return FinancialObligation(
    id: id,
    sourceEventIds: ['sms-$id'],
    obligationType: ObligationType.creditCardDue,
    title: '$merchant — Due',
    merchant: FieldConfidence<String>(
      value: merchant,
      confidence: 0.9,
      source: EvidenceSource.regexOnly,
    ),
    amount: FieldConfidence<double>(
      value: amount,
      confidence: 0.9,
      source: EvidenceSource.regexOnly,
    ),
    dueDate: dueDate == null
        ? const ResolvedObligationDate.unknown()
        : ResolvedObligationDate(
            value: dueDate,
            kind: ObligationDateKind.dueDate,
            confidence: 0.9,
          ),
    recurrence: ObligationRecurrence.singleObservation(now),
    accountMatch: const FieldConfidence<String>.unknown(),
    paymentMethod: const FieldConfidence.unknown(),
    referenceNumber: referenceNumber,
    status: status,
    confidence: 0.8,
    evidence: const [],
    source: ObligationSource.smsDetected,
    reviewReasons: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late InMemoryObligationRepository repository;
  late ObligationLinker linker;

  setUp(() {
    repository = InMemoryObligationRepository();
    linker = ObligationLinker(repository);
  });

  test('links by reference number as the strongest signal', () async {
    await repository.upsert(
      _obligation(
        id: 'o1',
        merchant: 'HDFC Credit Card',
        amount: 8000,
        referenceNumber: 'UTR123',
      ),
    );

    final outcome = await linker.link(
      amount: 8000,
      merchantOrSender: 'HDFC Credit Card',
      completedAt: DateTime(2026, 9, 5),
      referenceNumber: 'UTR123',
    );

    expect(outcome.result, ObligationLinkResult.linkedResolved);
    expect(outcome.matchedObligationId, 'o1');
  });

  test('links by merchant + amount within the lookback window', () async {
    await repository.upsert(
      _obligation(
        id: 'o2',
        merchant: 'HDFC Credit Card',
        amount: 8000,
        dueDate: DateTime(2026, 8, 20),
      ),
    );

    final outcome = await linker.link(
      amount: 8000,
      merchantOrSender: 'HDFC Credit Card',
      completedAt: DateTime(2026, 9, 5),
    );

    expect(outcome.result, ObligationLinkResult.linkedResolved);
    expect(outcome.matchedObligationId, 'o2');
  });

  test('does not link when the amount differs', () async {
    await repository.upsert(
      _obligation(id: 'o3', merchant: 'HDFC Credit Card', amount: 8000),
    );

    final outcome = await linker.link(
      amount: 7500,
      merchantOrSender: 'HDFC Credit Card',
      completedAt: DateTime(2026, 9, 1),
    );

    expect(outcome.result, ObligationLinkResult.noMatch);
  });

  test(
    'does not link an already-resolved (non-outstanding) obligation',
    () async {
      await repository.upsert(
        _obligation(
          id: 'o4',
          merchant: 'HDFC Credit Card',
          amount: 8000,
          status: ObligationStatus.completed,
        ),
      );

      final outcome = await linker.link(
        amount: 8000,
        merchantOrSender: 'HDFC Credit Card',
        completedAt: DateTime(2026, 9, 1),
      );

      expect(outcome.result, ObligationLinkResult.noMatch);
    },
  );

  test(
    'surfaces multiple same-merchant-and-amount candidates as possibleMatch, never silently picks one',
    () async {
      await repository.upsert(
        _obligation(
          id: 'o5a',
          merchant: 'Netflix',
          amount: 649,
          dueDate: DateTime(2026, 8, 1),
        ),
      );
      await repository.upsert(
        _obligation(
          id: 'o5b',
          merchant: 'Netflix',
          amount: 649,
          dueDate: DateTime(2026, 9, 1),
        ),
      );

      final outcome = await linker.link(
        amount: 649,
        merchantOrSender: 'Netflix',
        completedAt: DateTime(2026, 9, 2),
      );

      expect(outcome.result, ObligationLinkResult.possibleMatch);
    },
  );

  test(
    'marking resolved sets status completed and links the event id',
    () async {
      await repository.upsert(
        _obligation(id: 'o6', merchant: 'HDFC Credit Card', amount: 8000),
      );

      final resolved = await repository.markResolved(
        id: 'o6',
        linkedEventId: 'evt-1',
        resolvedAt: DateTime(2026, 9, 5),
      );

      expect(resolved.status, ObligationStatus.completed);
      expect(resolved.linkedEventId, 'evt-1');
      expect((await repository.getOutstanding()), isEmpty);
    },
  );

  test('insufficient signal (no amount) never matches', () async {
    await repository.upsert(
      _obligation(id: 'o7', merchant: 'HDFC Credit Card', amount: 8000),
    );

    final outcome = await linker.link(
      amount: null,
      merchantOrSender: 'HDFC Credit Card',
      completedAt: DateTime(2026, 9, 1),
    );

    expect(outcome.result, ObligationLinkResult.noMatch);
  });
}
