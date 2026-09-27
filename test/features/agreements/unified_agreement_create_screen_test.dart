// Unified "Add Loan / Installment" full-page wizard: small-screen layout,
// light/dark themes, the explicit account-movement toggle, one-time
// repayment, inline Add Person entry, keyboard traversal, the submit
// processing state, and an end-to-end create through the real
// LoanRepository.createAgreementWithOrigination on a fake Firestore.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/agreements/presentation/screens/unified_agreement_create_screen.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'uid';

/// Holds every transaction until [gate] completes, so the in-flight UI state
/// is observable (the plain fake resolves inside a single frame).
class _GatedFirestore extends FakeFirebaseFirestore {
  Completer<void>? gate;
  var transactionCalls = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionCalls++;
    await gate?.future;
    return super.runTransaction(transactionHandler);
  }
}

Future<_GatedFirestore> _seeded() async {
  final firestore = _GatedFirestore();
  final user = firestore.collection('users').doc(_uid);
  await user
      .collection('accounts')
      .doc('hdfc')
      .set(
        Account(
          id: 'hdfc',
          name: 'HDFC',
          type: AccountType.bank,
          openingBalance: 100000,
          currentBalance: 100000,
          colorValue: 0,
          createdAt: DateTime(2026),
        ).toFirestore(),
      );
  await user
      .collection('accounts')
      .doc('card')
      .set(
        Account(
          id: 'card',
          name: 'Card account',
          type: AccountType.card,
          openingBalance: 0,
          currentBalance: 0,
          colorValue: 0,
          createdAt: DateTime(2026),
        ).toFirestore(),
      );
  await user
      .collection('people')
      .doc('rahul')
      .set(
        Person(
          id: 'rahul',
          name: 'Rahul',
          avatarColorValue: 0,
          openingBalance: 0,
          currentBalance: 0,
          createdAt: DateTime(2026),
        ).toFirestore(),
      );
  return firestore;
}

Widget _app(
  FakeFirebaseFirestore firestore, {
  ThemeData? theme,
  UnifiedCreateKind? kind = UnifiedCreateKind.borrowed,
}) => ProviderScope(
  overrides: [
    firestoreProvider.overrideWithValue(firestore),
    currentUserIdProvider.overrideWithValue(_uid),
  ],
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UnifiedAgreementCreateScreen(initialKind: kind),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _toTerms(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> _fillBorrowed(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Name / purpose'),
    'Home renovation',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Provider'),
    'HDFC Bank',
  );
  await tester.enterText(find.widgetWithText(TextField, 'Principal'), '50000');
  await tester.pumpAndSettle();
}

void _useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

FilledButton _primary(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  testWidgets(
    'small screen (320x640), light: terms step lays out without overflow',
    (tester) async {
      _useSmallScreen(tester);
      await _open(tester, _app(await _seeded()));
      await _toTerms(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Agreement details'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Record money received in an account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dark theme renders the wizard', (tester) async {
    await _open(tester, _app(await _seeded(), theme: AppTheme.dark));
    await _toTerms(tester);
    expect(
      Theme.of(tester.element(find.text('Agreement details'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'movement toggle: account picker appears only when enabled and is then required; card accounts are not offered',
    (tester) async {
      await _open(tester, _app(await _seeded()));
      await _toTerms(tester);
      await _fillBorrowed(tester);
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Account'),
        findsNothing,
      );
      expect(_primary(tester).onPressed, isNotNull);

      await tester.scrollUntilVisible(
        find.byType(SwitchListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Choose the account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_primary(tester).onPressed, isNull);

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Account'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Card account'), findsNothing);
      await tester.tap(find.text('HDFC').last);
      await tester.pumpAndSettle();
      expect(_primary(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'one-time repayment swaps the payment count for a repay-by date',
    (tester) async {
      await _open(tester, _app(await _seeded()));
      await _toTerms(tester);
      expect(
        find.widgetWithText(TextField, 'Monthly payments'),
        findsOneWidget,
      );
      await tester.tap(find.text('One-time'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Monthly payments'), findsNothing);
      expect(find.text('Repay by'), findsOneWidget);
    },
  );

  testWidgets(
    'lent: the Person picker offers the existing Add Person flow inline',
    (tester) async {
      await _open(tester, _app(await _seeded(), kind: UnifiedCreateKind.lent));
      await _toTerms(tester);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Person'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rahul').last, findsOneWidget);
      expect(find.text('Add new person'), findsOneWidget);
      expect(find.text('Record money sent from an account'), findsNothing);
    },
  );

  testWidgets('keyboard: "next" moves focus from name to the next field', (
    tester,
  ) async {
    await _open(tester, _app(await _seeded()));
    await _toTerms(tester);
    await tester.tap(find.widgetWithText(TextField, 'Name / purpose'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus;
    final provider = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Provider'),
    );
    expect(focused, provider.focusNode ?? isNotNull);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.widgetWithText(TextField, 'Name / purpose'),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isFalse,
    );
  });

  testWidgets(
    'end-to-end: review shows the movement; Create shows the processing state, writes once, and closes',
    (tester) async {
      final firestore = await _seeded();
      await _open(tester, _app(firestore));
      await _toTerms(tester);
      await _fillBorrowed(tester);
      await tester.scrollUntilVisible(
        find.byType(SwitchListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Account'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('HDFC').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Account movement: HDFC +₹50000.00'), findsOneWidget);
      firestore.gate = Completer<void>();
      await tester.tap(find.text('Create agreement'));
      await tester.pump();
      expect(find.text('Creating…'), findsOneWidget);
      expect(_primary(tester).onPressed, isNull);
      // A second tap while in flight is ignored (the button is disabled).
      await tester.tap(find.text('Creating…'), warnIfMissed: false);
      await tester.pump();
      firestore.gate!.complete();
      await tester.pumpAndSettle();

      expect(firestore.transactionCalls, 1);
      expect(find.text('open'), findsOneWidget);
      final user = firestore.collection('users').doc(_uid);
      expect((await user.collection('loans').get()).size, 1);
      expect((await user.collection('transactions').get()).size, 1);
      expect(
        (await user.collection('accounts').doc('hdfc').get())
            .data()!['currentBalance'],
        150000,
      );
    },
  );
}
