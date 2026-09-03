import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Structural proof that the merchant-learning tables cannot hold raw SMS
/// body, OTP/CVV/PIN/password, a full account/card number, a phone number,
/// or a raw AI prompt/response — only normalized merchant identity and
/// learning metadata, matching `MerchantLearningProfile`/`LearnedField`/
/// `CorrectionEvent`'s own privacy-safe shape. Asserts against the live
/// schema (not just the CREATE TABLE source) so a future ALTER TABLE adding
/// a forbidden column would fail this test.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SmsInboxDatabase.debugReset();
  });

  final forbiddenNeedles = <String>[
    'body',
    'sms',
    'otp',
    'cvv',
    'pin',
    'password',
    'account_number',
    'card_number',
    'phone',
    'mobile',
    'prompt',
    'ai_response',
    'ai_raw',
  ];

  Future<List<String>> columnsOf(String table) async {
    final db = await SmsInboxDatabase.openInMemoryForTest();
    final info = await db.database.rawQuery('PRAGMA table_info($table)');
    final columns = info.map((row) => row['name']! as String).toList();
    await db.database.close();
    return columns;
  }

  test('merchant_learning_profiles has no column matching a forbidden needle', () async {
    final columns = await columnsOf(
      SmsInboxDatabase.merchantLearningProfilesTableName,
    );
    for (final column in columns) {
      final lower = column.toLowerCase();
      for (final needle in forbiddenNeedles) {
        expect(
          lower.contains(needle),
          isFalse,
          reason: 'column "$column" looks like it could hold sensitive data (matches "$needle")',
        );
      }
    }
  });

  test('merchant_learning_corrections has no column matching a forbidden needle', () async {
    final columns = await columnsOf(
      SmsInboxDatabase.merchantLearningCorrectionsTableName,
    );
    for (final column in columns) {
      final lower = column.toLowerCase();
      for (final needle in forbiddenNeedles) {
        expect(
          lower.contains(needle),
          isFalse,
          reason: 'column "$column" looks like it could hold sensitive data (matches "$needle")',
        );
      }
    }
  });

  test('merchant_learning_profiles columns are exactly the expected privacy-safe set', () async {
    final columns = await columnsOf(
      SmsInboxDatabase.merchantLearningProfilesTableName,
    );
    expect(
      columns.toSet(),
      {
        'user_id',
        'merchant_key',
        for (final prefix in [
          'merchant_type',
          'category',
          'subcategory',
          'payment_provider',
          'payment_method',
        ]) ...[
          '${prefix}_value',
          '${prefix}_source',
          '${prefix}_confirmations',
          '${prefix}_corrections',
          '${prefix}_last_updated_at',
        ],
      },
    );
  });

  test('merchant_learning_corrections columns are exactly the expected privacy-safe set', () async {
    final columns = await columnsOf(
      SmsInboxDatabase.merchantLearningCorrectionsTableName,
    );
    expect(
      columns.toSet(),
      {'id', 'user_id', 'merchant_key', 'field', 'old_value', 'new_value', 'source', 'timestamp'},
    );
  });
}
