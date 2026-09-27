import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/agreements/domain/unified_workspace_model.dart';
import 'package:finance_app/features/agreements/presentation/widgets/unified_agreement_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const summary = UnifiedAgreementSummary(
  liabilityPrincipal: 128000,
  receivablePrincipal: 25000,
  dueSoonAmount: 8450,
  dueSoonCount: 2,
  overdueAmount: 1200,
  overdueCount: 1,
);

Widget subject(ThemeData theme) => MaterialApp(
  theme: theme,
  home: const Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: UnifiedAgreementSummaryCard(summary: summary),
      ),
    ),
  ),
);

void main() {
  testWidgets('20 summary has no overflow at narrow mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(subject(AppTheme.light));
    expect(tester.takeException(), isNull);
    expect(find.text('I Owe'), findsOneWidget);
  });

  testWidgets('21 summary renders in light theme', (tester) async {
    await tester.pumpWidget(subject(AppTheme.light));
    expect(find.text('Owed to Me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('22 summary renders in dark theme', (tester) async {
    await tester.pumpWidget(subject(AppTheme.dark));
    expect(find.textContaining('Overdue'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('I Owe'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}
