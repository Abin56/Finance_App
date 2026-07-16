import 'package:finance_app/core/data/bank_registry.dart';
import 'package:finance_app/shared/widgets/bank_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<String?> pumpAndOpenPicker(WidgetTester tester, {String? currentBankId}) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await BankPickerSheet.show(context, currentBankId: currentBankId);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the frequently used section before browsing', (tester) async {
    await pumpAndOpenPicker(tester);

    expect(find.text('Frequently used'), findsOneWidget);
    expect(find.text('State Bank of India'), findsOneWidget);
  });

  testWidgets('search filters the list by name', (tester) async {
    await pumpAndOpenPicker(tester);

    await tester.enterText(find.byType(TextField), 'kotak');
    await tester.pumpAndSettle();

    expect(find.text('Kotak Mahindra Bank'), findsOneWidget);
    expect(find.text('State Bank of India'), findsNothing);
  });

  testWidgets('search filters the list by short code', (tester) async {
    await pumpAndOpenPicker(tester);

    await tester.enterText(find.byType(TextField), 'HDFC');
    await tester.pumpAndSettle();

    expect(find.text('HDFC Bank'), findsOneWidget);
  });

  testWidgets('shows a no-results message when nothing matches', (tester) async {
    await pumpAndOpenPicker(tester);

    await tester.enterText(find.byType(TextField), 'zzzznotabank');
    await tester.pumpAndSettle();

    expect(find.text('No banks match your search'), findsOneWidget);
  });

  testWidgets('selecting a bank row pops its bankId', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await BankPickerSheet.show(context);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Axis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Axis Bank'));
    await tester.pumpAndSettle();

    expect(result, 'axis');
  });

  testWidgets('picking "Other / Generic Bank" returns the generic id', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await BankPickerSheet.show(context, currentBankId: 'sbi');
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Other / Generic Bank'));
    await tester.pumpAndSettle();

    expect(result, BankRegistry.generic.id);
  });
}
