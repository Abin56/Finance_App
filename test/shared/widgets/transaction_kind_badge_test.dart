import 'package:finance_app/shared/domain/transaction_kind.dart';
import 'package:finance_app/shared/widgets/states/transaction_kind_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, TransactionKind kind, {bool compact = false, double scale = 1.0}) {
    return tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: TransactionKindBadge(kind: kind, compact: compact)),
      ),
    );
  }

  for (final kind in TransactionKind.values) {
    testWidgets('renders the correct label and icon for $kind', (tester) async {
      await pump(tester, kind);

      expect(find.text(kind.label), findsOneWidget);
      expect(find.byIcon(kind.icon), findsOneWidget);
    });
  }

  testWidgets('applies the kind\'s color to both icon and text', (tester) async {
    await pump(tester, TransactionKind.myExpense);

    final icon = tester.widget<Icon>(find.byIcon(TransactionKind.myExpense.icon));
    expect(icon.color, TransactionKind.myExpense.color);

    final text = tester.widget<Text>(find.text(TransactionKind.myExpense.label));
    expect(text.style?.color, TransactionKind.myExpense.color);
  });

  testWidgets('compact mode uses smaller padding/icon size than default', (tester) async {
    await pump(tester, TransactionKind.bill, compact: true);
    final compactIcon = tester.widget<Icon>(find.byIcon(TransactionKind.bill.icon));

    await pump(tester, TransactionKind.bill);
    final defaultIcon = tester.widget<Icon>(find.byIcon(TransactionKind.bill.icon));

    expect(compactIcon.size, lessThan(defaultIcon.size!));
  });

  testWidgets('does not overflow at a large accessibility text scale', (tester) async {
    await pump(tester, TransactionKind.creditCard, scale: 2.0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(TransactionKind.creditCard.label), findsOneWidget);
  });

  testWidgets('label truncates with ellipsis rather than overflowing when width is constrained', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 40,
            child: TransactionKindBadge(kind: TransactionKind.splitExpense, compact: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders correctly against a dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: TransactionKindBadge(kind: TransactionKind.loan)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(TransactionKind.loan.label), findsOneWidget);
  });
}
