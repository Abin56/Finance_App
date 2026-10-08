// Golden People Ledger payment / advance rule — byte-identical copy of the web
// app's `tests/cross-platform-fixtures/person-payment-fixture.json`, so the
// Dart and TypeScript engines give one answer for the same data.
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/features/people/domain/person_cycle_statement.dart';
import 'package:finance_app/features/people/domain/person_payment.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _day(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

double _n(dynamic v) => (v as num).toDouble();

void main() {
  final fixture = jsonDecode(
    File('test/cross_platform_fixtures/person_payment_fixture.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final person = fixture['person'] as Map<String, dynamic>;
  final cycles = {
    for (final e in (fixture['cycles'] as Map<String, dynamic>).entries)
      e.key: StatementCycle(_day(e.value['start'] as String), _day(e.value['end'] as String)),
  };

  StatementLedgerInput ledgerEntry(Map<String, dynamic> j) => StatementLedgerInput(
        id: j['id'] as String,
        type: j['type'] as String,
        amount: _n(j['amount']),
        date: _day(j['date'] as String),
        createdAt: _day(j['createdAt'] as String),
        note: j['note'] as String? ?? '',
        transactionRef: j['transactionRef'] as String?,
        parentEntryId: j['parentEntryId'] as String?,
        sourceKind: j['sourceKind'] as String?,
        obligationRef: j['obligationRef'] as String?,
        paymentId: j['paymentId'] as String?,
      );

  for (final c in (fixture['statementCases'] as List).cast<Map<String, dynamic>>()) {
    for (final entry in (c['expect'] as Map<String, dynamic>).entries) {
      test('${c['name']} — ${entry.key}', () {
        final s = buildPersonCycleStatement(
          personId: person['id'] as String,
          openingBalance: _n(person['openingBalance']),
          personCreatedAt: _day(person['createdAt'] as String),
          ledger: [for (final id in (c['ledger'] as List).cast<String>()) ledgerEntry(fixture['ledger'][id] as Map<String, dynamic>)],
          emis: [
            for (final e in (fixture['emis'] as List).cast<Map<String, dynamic>>())
              StatementEmiSource(
                id: e['id'] as String,
                name: e['name'] as String,
                scheduleId: e['scheduleId'] as String,
                beneficiaryPersonId: e['beneficiaryPersonId'] as String?,
                beneficiaryRepaysInstallments: e['beneficiaryRepaysInstallments'] as bool,
              ),
          ],
          installments: [
            for (final id in (c['installments'] as List).cast<String>())
              () {
                final i = fixture['installments'][id] as Map<String, dynamic>;
                return StatementInstallment(
                  id: i['id'] as String,
                  scheduleId: i['scheduleId'] as String,
                  sequenceNumber: i['sequenceNumber'] as int,
                  dueDate: _day(i['dueDate'] as String),
                  amountDue: _n(i['amountDue']),
                  amountPaid: _n(i['amountPaid']),
                  createdAt: _day(i['createdAt'] as String),
                );
              }(),
          ],
          advanceApplications: [
            for (final id in (c['applications'] as List).cast<String>())
              () {
                final a = fixture['applications'][id] as Map<String, dynamic>;
                return AdvanceApplicationInput(
                  id: a['id'] as String,
                  advanceEntryId: a['advanceEntryId'] as String,
                  obligationKey: a['obligationKey'] as String,
                  amount: _n(a['amount']),
                  date: _day(a['date'] as String),
                  createdAt: _day(a['createdAt'] as String),
                );
              }(),
          ],
          cycle: cycles[entry.key]!,
        );
        final e = entry.value as Map<String, dynamic>;
        final actual = {
          'previousPending': s.previousPending,
          'cycleActivity': s.cycleActivity,
          'cycleSettlements': s.cycleSettlements,
          'currentPending': s.currentPending,
          'previousAdvance': s.previousAdvance,
          'advanceBalance': s.advanceBalance,
          'cashReceived': s.cashReceived,
          'cashPaid': s.cashPaid,
        };
        for (final k in actual.keys) {
          expect(actual[k], _n(e[k]), reason: k);
        }
        for (final r in (e['remainingNow'] as Map<String, dynamic>).entries) {
          expect(s.rows.firstWhere((row) => row.key == r.key).remainingNow, _n(r.value), reason: r.key);
        }
      });
    }
  }

  final obligations = [
    for (final o in (fixture['allocationObligations'] as List).cast<Map<String, dynamic>>())
      PaymentObligation(
        key: o['key'] as String,
        title: o['title'] as String,
        date: _day(o['date'] as String),
        createdAt: _day(o['createdAt'] as String),
        amount: _n(o['amount']),
        outstanding: _n(o['outstanding']),
        side: ObligationSide.values.byName(o['side'] as String),
      ),
  ];
  for (final c in (fixture['allocationCases'] as List).cast<Map<String, dynamic>>()) {
    test('allocation — ${c['name']}', () {
      final manual = (c['manual'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, _n(v)));
      final a = allocatePayment(
        obligations: obligations,
        selectedKeys: obligations.map((o) => o.key),
        amount: _n(c['amount']),
        manual: manual,
      );
      final e = c['expect'] as Map<String, dynamic>;
      expect([for (final l in a.lines) [l.key, l.amount]], [for (final l in (e['lines'] as List)) [l[0], _n(l[1])]]);
      expect(a.selectedTotal, _n(e['selectedTotal']));
      expect(a.allocated, _n(e['allocated']));
      expect(a.extra, _n(e['extra']));
      expect(a.unpaid, _n(e['unpaid']));
      expect(a.outcome.name, e['outcome']);
      expect(a.error, isNull);
    });
  }
}
