import 'package:finance_app/features/sms_inbox/data/financial_event_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_evidence_link.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the v4->v5 upgrade (adding `financial_events`/
/// `sms_financial_event_links`) against a real shipped v4 database: purely
/// additive — every existing `sms_inbox` row untouched, and the two new
/// tables are immediately usable. Mirrors
/// `transaction_candidate_migration_test.dart`'s role for the v3->v4 step.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String path;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    path = await databaseFactory.getDatabasesPath();
    path =
        '$path/financial_event_migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  Future<void> seedV4Row(String id) async {
    final db = await SmsInboxDatabase.openV4ForTest(path);
    await db.insert(SmsInboxDatabase.tableName, {
      'id': id,
      'message_key': 'key-$id',
      'dedup_key': 'dedup-$id',
      'sender': 'VM-HDFCBK',
      'body': 'Rs.1,250.00 debited from a/c XX5623.',
      'received_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
      'direction': 'debit',
      'amount': 1250.0,
      'status': 'imported',
      'linked_entity_id': 'txn-99',
      'created_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
    });
    await db.close();
  }

  test('v4->v5 preserves every existing sms_inbox row untouched', () async {
    await seedV4Row('row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final items = await SmsInboxDao(database).getAll();
    await database.database.close();

    expect(items, hasLength(1));
    expect(items.single.id, 'row-1');
    expect(items.single.linkedEntityId, 'txn-99');
  });

  test('v4->v5 creates a usable, empty financial_events/links pair', () async {
    await seedV4Row('row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final dao = FinancialEventDao(database);

    expect(await dao.getAll(), isEmpty);

    final event = FinancialEvent(
      id: 'evt-1',
      primarySmsItemId: 'row-1',
      eventType: FinancialEventType.payment,
      role: FinancialEventRole.standalone,
      status: FinancialEventStatus.pendingReview,
      direction: SmsTransactionDirection.debit,
      amount: const FieldConfidence(
        value: 1250,
        confidence: 0.85,
        source: EvidenceSource.regexOnly,
      ),
      merchant: const FieldConfidence.unknown(),
      category: const FieldConfidence.unknown(),
      paymentMethod: const FieldConfidence<PaymentMethod>.unknown(),
      accountMatch: const FieldConfidence.unknown(),
      moneyMovement: const FieldConfidence(
        value: true,
        confidence: 0.85,
        source: EvidenceSource.regexOnly,
      ),
      transactionStatus: const FieldConfidence.unknown(),
      eventDate: DateTime(2026, 7, 15),
      overallConfidence: 0.5,
      confidenceLevel: ConfidenceLevel.medium,
      automationAction: AutomationAction.needsReview,
      needsReview: true,
      reviewReasons: const [],
      createdAt: DateTime(2026, 7, 15),
    );
    await dao.upsert(event);
    await dao.linkSms(
      FinancialEventEvidenceLink(
        id: 'link-1',
        financialEventId: 'evt-1',
        smsItemId: 'row-1',
        linkType: FinancialEventLinkType.newEvent,
        confidence: 0.5,
        linkedAt: DateTime(2026, 7, 15),
      ),
    );

    final all = await dao.getAll();
    final links = await dao.getLinksForEvent('evt-1');
    await database.database.close();

    expect(all, hasLength(1));
    expect(all.single.id, 'evt-1');
    expect(links, hasLength(1));
    expect(links.single.smsItemId, 'row-1');
  });

  test(
    'a fresh install (no prior database) also gets the financial_events tables',
    () async {
      final database = await SmsInboxDatabase.openInMemoryForTest();
      final dao = FinancialEventDao(database);

      expect(await dao.getAll(), isEmpty);
      await database.database.close();
    },
  );

  test(
    'v5->v6 preserves an existing financial_events row and adds the new columns as null/default',
    () async {
      final v5db = await SmsInboxDatabase.openV5ForTest(path);
      await v5db.insert(SmsInboxDatabase.tableName, {
        'id': 'row-1',
        'message_key': 'key-row-1',
        'dedup_key': 'dedup-row-1',
        'sender': 'VM-HDFCBK',
        'body': 'Rs.1,250.00 debited from a/c XX5623.',
        'received_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
        'status': 'pending',
        'created_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
      });
      await v5db.insert(SmsInboxDatabase.financialEventsTableName, {
        'id': 'evt-1',
        'primary_sms_item_id': 'row-1',
        'event_type': 'payment',
        'role': 'standalone',
        'status': 'pendingReview',
        'direction': 'debit',
        'amount': 1250.0,
        'amount_confidence': 0.85,
        'amount_source': 'regexOnly',
        'event_date': DateTime(2026, 7, 15).millisecondsSinceEpoch,
        'overall_confidence': 0.5,
        'confidence_level': 'medium',
        'automation_action': 'needsReview',
        'needs_review': 1,
        'created_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
      });
      await v5db.close();

      final database = await SmsInboxDatabase.openUpgradedForTest(path);
      final dao = FinancialEventDao(database);
      final all = await dao.getAll();
      await database.database.close();

      expect(all, hasLength(1));
      final migrated = all.single;
      expect(migrated.id, 'evt-1');
      expect(
        migrated.amount.value,
        1250.0,
        reason: 'a pre-v6 row is untouched by the additive column migration',
      );
      // The new columns did not exist on this row before the migration, so
      // they read back as the honest "unknown" state — never a guessed value.
      expect(migrated.moneyMovement.value, isNull);
      expect(migrated.transactionStatus.value, isNull);
      expect(
        migrated.isOwnAccountTransfer,
        isFalse,
        reason: 'NOT NULL DEFAULT 0 on the new column',
      );
    },
  );
}
