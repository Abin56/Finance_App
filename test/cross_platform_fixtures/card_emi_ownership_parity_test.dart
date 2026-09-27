// Cross-platform parity for card-linked EMI liability ownership
// (`purchaseTransactionId`). flowfi-web runs the same byte-identical fixture
// through its engines (tests/cross-platform-fixtures/golden-fixture-parity.test.ts,
// "card-linked EMI ownership"); here every case is built through Finance_App's
// REAL repositories and read back from its REAL Riverpod providers
// (creditCardStandingProvider, lockedEmiPrincipalForCardProvider,
// creditUtilizationPercentProvider, netWorthWithLoansProvider).
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/reports/presentation/providers/monthly_financial_report_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/cross_platform_fixtures/card_emi_ownership_fixture.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final fixture = _fixture();

  test('Web-shaped EMI doc → Flutter: purchaseTransactionId parses; a legacy doc without the key reads null', () async {
    final firestore = FakeFirebaseFirestore();
    final raw = Map<String, dynamic>.from(fixture['rawEmiDocWithLink'] as Map)
      ..['startDate'] = Timestamp.fromMillisecondsSinceEpoch(1767225600000)
      ..['endDate'] = Timestamp.fromMillisecondsSinceEpoch(1796083200000)
      ..['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(1767225600000);
    await firestore.collection('raw').doc('emi-1').set(raw);
    final emi = Emi.fromFirestore(await firestore.collection('raw').doc('emi-1').get(), null);
    expect(emi.purchaseTransactionId, 'txn-purchase-1');
    expect(emi.linkedCreditCardId, 'card-1');
    // Flutter → Web: Flutter writes the exact same key back.
    expect(emi.toFirestore()['purchaseTransactionId'], 'txn-purchase-1');

    raw.remove('purchaseTransactionId');
    await firestore.collection('raw').doc('emi-legacy').set(raw);
    final legacy = Emi.fromFirestore(await firestore.collection('raw').doc('emi-legacy').get(), null);
    expect(legacy.purchaseTransactionId, isNull);
  });

  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () async {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      final now = DateTime.now();

      final accounts = container.read(accountRepositoryProvider);
      await accounts.createAccount(
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: (fixture['bankBalance'] as num).toDouble(),
        colorValue: 0xFF000000,
      );
      final cardAccount = await accounts.createAccount(
        name: 'HDFC',
        type: AccountType.card,
        openingBalance: 0,
        colorValue: 0xFF000000,
      );
      final card = await container.read(creditCardRepositoryProvider).createCard(
            accountId: cardAccount.id,
            statementDay: 5,
            paymentDueDay: 25,
            creditLimit: (fixture['creditLimit'] as num).toDouble(),
          );

      final transactions = container.read(transactionRepositoryProvider);
      final purchaseIds = <String, String>{};
      for (final p in (c['purchases'] as List).cast<Map<String, dynamic>>()) {
        final txn = await transactions.createTransaction(
          type: TransactionType.expense,
          amount: (p['amount'] as num).toDouble(),
          dateTime: now,
          accountId: cardAccount.id,
          categoryId: 'shopping',
          description: 'Purchase ${p['key']}',
        );
        purchaseIds[p['key'] as String] = txn.id;
        if (p['deleted'] as bool) await transactions.softDeleteTransaction(txn);
      }

      final emiRepository = container.read(emiRepositoryProvider);
      for (final e in (c['emis'] as List).cast<Map<String, dynamic>>()) {
        final purchaseKey = e['purchaseKey'] as String?;
        final emi = await emiRepository.createEmi(
          name: 'EMI',
          principalAmount: (e['principal'] as num).toDouble(),
          startDate: now,
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 12,
          linkedCreditCardId: card.id,
          purchaseTransactionId: purchaseKey == null ? null : purchaseIds[purchaseKey],
        );
        if (e['legacyNoField'] as bool) {
          await firestore
              .collection('users')
              .doc(container.read(currentUserIdProvider))
              .collection('emis')
              .doc(emi.id)
              .update({'purchaseTransactionId': FieldValue.delete()});
        }
        final paid = (e['emiPaid'] as num).toDouble();
        if (paid > 0) {
          final installments = await container.read(installmentsStreamProvider(emi.scheduleId).future);
          final first = ([...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber))).first;
          final key = (scheduleId: emi.scheduleId, installmentId: first.id);
          await container.read(installmentPaymentRepositoryProvider(key)).recordPayment(first, amount: paid, date: now);
        }
      }

      // Keep every provider the figures depend on alive, then let the fake
      // Firestore streams settle.
      final subs = [
        container.listen(creditCardStandingProvider(card.id), (_, _) {}),
        container.listen(lockedEmiPrincipalForCardProvider(card.id), (_, _) {}),
        container.listen(creditUtilizationPercentProvider, (_, _) {}),
        container.listen(netWorthWithLoansProvider, (_, _) {}),
        container.listen(loansStreamProvider, (_, _) {}),
      ];
      addTearDown(() {
        for (final s in subs) {
          s.close();
        }
      });
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final expected = c['expected'] as Map<String, dynamic>;
      final standing = container.read(creditCardStandingProvider(card.id));
      final locked = container.read(lockedEmiPrincipalForCardProvider(card.id));
      expect(standing.outstanding, expected['outstanding']);
      expect(locked, expected['lockedEmiPrincipal']);
      expect(standing.outstanding + locked, expected['exposure']);
      expect(standing.available, expected['available']);
      expect(
        container.read(creditUtilizationPercentProvider),
        closeTo((expected['utilizationPercent'] as num).toDouble(), 1e-6),
      );
      expect(container.read(netWorthWithLoansProvider), expected['netWorth']);
    });
  }
}
