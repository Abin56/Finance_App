import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/accounts/presentation/widgets/account_form_sheet.dart';

/// Once a bank is picked for a Bank/Card-type account, the account's name
/// is computed from the bank + last-4 digits rather than typed — see
/// [bankAccountDisplayName]. This guards that the manual "Account name"
/// field actually disappears (not just that the computed string is
/// correct, which `bank_registry_test.dart` already covers) and that it
/// comes back for account types with no bank to compute from.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountsStreamProvider.overrideWith((ref) => Stream.value(const []))],
        child: const MaterialApp(home: Scaffold(body: AccountFormSheet())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Cash type (default) shows the manual Account name field', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(TextFormField, 'Account name'), findsOneWidget);
    expect(find.textContaining('Shown as'), findsNothing);
  });

  testWidgets('picking a bank for a Bank-type account hides the name field and shows a preview', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank Account').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Account name'), findsOneWidget);

    await tester.tap(find.text('Select bank (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State Bank of India'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Account name'), findsNothing);
    expect(find.text('Shown as "SBI Account"'), findsOneWidget);
  });
}
