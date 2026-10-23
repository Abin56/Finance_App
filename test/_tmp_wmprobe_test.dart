// TEMPORARY read-only probe (deleted after use): WorkManager job states only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('wm probe', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(Platform.environment['PROBE_DB']!);
    String t(int? ms) => ms == null || ms == 0 ? '-' : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String().substring(11, 19);
    final byState = await db.rawQuery(
      "SELECT state, COUNT(*) c FROM WorkSpec WHERE worker_class_name LIKE '%SmsScanWorker' GROUP BY state",
    );
    // ignore: avoid_print
    print('WMPROBE states(0=enq,1=run,2=succ,3=fail,4=blocked,5=cancel)=${byState.map((r) => '${r['state']}:${r['c']}').join(',')}');
    final rows = await db.rawQuery(
      "SELECT state, last_enqueue_time, initial_delay, run_attempt_count, schedule_requested_at "
      "FROM WorkSpec WHERE worker_class_name LIKE '%SmsScanWorker' ORDER BY last_enqueue_time DESC LIMIT 12",
    );
    for (final r in rows) {
      // ignore: avoid_print
      print('WMPROBE state=${r['state']} enqueued=${t(r['last_enqueue_time'] as int?)} delay=${r['initial_delay']} attempts=${r['run_attempt_count']}');
    }
    final dep = await db.rawQuery('SELECT COUNT(*) c FROM Dependency');
    // ignore: avoid_print
    print('WMPROBE dependencies=${dep.first['c']}');
    await db.close();
  });
}
