import 'package:finance_app/shared/widgets/dialogs/delete_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the entity name in the title and the required body copy', (tester) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    confirmDelete(capturedContext, entityName: 'Transaction');
    await tester.pumpAndSettle();

    expect(find.text('Delete Transaction?'), findsOneWidget);
    expect(
      find.text('This action moves it to Trash. You can restore it later.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
  });

  testWidgets('returns true when Delete is tapped', (tester) async {
    late BuildContext capturedContext;
    bool? result;

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            capturedContext = context;
            return ElevatedButton(
              onPressed: () async {
                result = await confirmDelete(capturedContext, entityName: 'Bill');
              },
              child: const Text('trigger'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('returns false when Cancel is tapped', (tester) async {
    late BuildContext capturedContext;
    bool? result;

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            capturedContext = context;
            return ElevatedButton(
              onPressed: () async {
                result = await confirmDelete(capturedContext, entityName: 'Loan');
              },
              child: const Text('trigger'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('returns false when dismissed without a choice (e.g. tapping the barrier)', (tester) async {
    late BuildContext capturedContext;
    bool? result;

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            capturedContext = context;
            return ElevatedButton(
              onPressed: () async {
                result = await confirmDelete(capturedContext, entityName: 'EMI');
              },
              child: const Text('trigger'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // Tap the modal barrier outside the dialog to dismiss it without a choice.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
