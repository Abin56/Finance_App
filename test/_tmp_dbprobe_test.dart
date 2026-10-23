// TEMPORARY read-only probe (deleted after use). Prints aggregates only —
// never bodies, senders, amounts or references.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

void main() {
  test('probe', () async {
    sqfliteFfiInit();
    final path = Platform.environment['PROBE_DB']!;
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    String fmt(int? ms) => ms == null
        ? '-'
        : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String().substring(11, 19);
    final total = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sms_inbox'),
    );
    final bySource = await db.rawQuery(
      'SELECT source, COUNT(*) c FROM sms_inbox GROUP BY source',
    );
    final byStatus = await db.rawQuery(
      'SELECT status, COUNT(*) c FROM sms_inbox GROUP BY status',
    );
    final parsed = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sms_inbox WHERE amount IS NOT NULL'),
    );
    final dup = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM sms_inbox WHERE duplicate_of_id IS NOT NULL',
      ),
    );
    final newest = await db.rawQuery(
      'SELECT source, received_at, created_at, '
      '(amount IS NOT NULL) AS parsed, (duplicate_of_id IS NOT NULL) AS dup, status '
      'FROM sms_inbox ORDER BY created_at DESC LIMIT 4',
    );
    // ignore: avoid_print
    print('PROBE total=$total parsed=$parsed duplicates=$dup');
    // ignore: avoid_print
    print('PROBE bySource=${bySource.map((r) => '${r['source']}:${r['c']}').join(',')}');
    // ignore: avoid_print
    print('PROBE byStatus=${byStatus.map((r) => '${r['status']}:${r['c']}').join(',')}');
    for (final r in newest) {
      // ignore: avoid_print
      print(
        'PROBE newest source=${r['source']} received=${fmt(r['received_at'] as int?)} '
        'created=${fmt(r['created_at'] as int?)} parsed=${r['parsed']} dup=${r['dup']} status=${r['status']}',
      );
    }
    await db.close();
  });
}
