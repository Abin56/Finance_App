// Cross-platform parity for People positions. flowfi-web loads a byte-identical
// copy of `person_position_fixture.json`
// (tests/cross-platform-fixtures/person-position-parity.test.ts); both must
// give identical per-person and total figures.
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/features/people/domain/person_position.dart';
import 'package:flutter_test/flutter_test.dart';

double _n(Object? v) => (v as num).toDouble();

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/cross_platform_fixtures/person_position_fixture.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final personId = fixture['personId'] as String;

  for (final s in (fixture['scenarios'] as List).cast<Map<String, dynamic>>()) {
    test(s['name'], () {
      final loans = [
        for (final l in (s['loans'] as List).cast<Map<String, dynamic>>())
          PositionLoan(
            id: l['id'] as String,
            personId: l['personId'] as String?,
            isGiven: l['direction'] == 'given',
            outstandingPrincipal: _n(l['outstandingPrincipal']),
            isDeleted: l['isDeleted'] as bool,
          ),
      ];
      final p = personPosition(
        personId: personId,
        currentBalance: _n(s['currentBalance']),
        loans: loans,
        ledgerEntries: [
          for (final e
              in (s['ledgerEntries'] as List).cast<Map<String, dynamic>>())
            PositionLedgerEntry(
              transactionRef: e['transactionRef'] as String?,
              signedAmount: _n(e['signedAmount']),
              isDeleted: e['isDeleted'] as bool,
            ),
        ],
        loanIds: {for (final l in loans) l.id},
      );
      final x = s['expected'] as Map<String, dynamic>;
      expect(p.directBalance, _n(x['directBalance']));
      expect(p.loanReceivable, _n(x['loanReceivable']));
      expect(p.loanPayable, _n(x['loanPayable']));
      expect(p.legacyLoanLedger, _n(x['legacyLoanLedger']));
      expect(p.net, _n(x['net']));
      expect(p.owesMe, _n(x['owesMe']));
      expect(p.iOwe, _n(x['iOwe']));
    });
  }

  test('people totals', () {
    final totals = fixture['totals'] as Map<String, dynamic>;
    final positions = [
      for (final p
          in (totals['positions'] as List).cast<Map<String, dynamic>>())
        PersonPosition(
          directBalance: 0,
          loanReceivable: 0,
          loanPayable: 0,
          legacyLoanLedger: 0,
          net: _n(p['owesMe']) - _n(p['iOwe']),
        ),
    ];
    final t = peopleTotals(positions);
    final x = totals['expected'] as Map<String, dynamic>;
    expect(t.totalOwedToMe, _n(x['totalOwedToMe']));
    expect(t.owedByCount, x['owedByCount']);
    expect(t.totalIOwe, _n(x['totalIOwe']));
    expect(t.owingCount, x['owingCount']);
    expect(t.net, _n(x['net']));
  });
}
