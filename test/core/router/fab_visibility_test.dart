import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/router/fab_visibility.dart';

/// The three Android widths the FAB overlap was reported across. The manager
/// is width-independent, but the sheets it uncovers are not, so the whole
/// matrix runs at each.
const _widths = <double>[360, 390, 412];

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  bool fabVisible() => container.read(fabVisibleProvider);

  /// Mirrors the real shell: a Navigator nested inside a Scaffold's body, the
  /// arrangement that makes branch sheets paint under the FAB's slot. Sheets
  /// opened here land on the nested navigator exactly as a tab screen's do.
  Widget harness() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Navigator(
            observers: [FabHidingModalObserver(container.read(modalRouteCountProvider.notifier))],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        builder: (sheetContext) => TextButton(
                          onPressed: () => showDialog<void>(
                            context: sheetContext,
                            useRootNavigator: false,
                            builder: (_) => const AlertDialog(content: Text('dialog')),
                          ),
                          child: const Text('open dialog'),
                        ),
                      ),
                      child: const Text('open sheet'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('page'))),
                      ),
                      child: const Text('open page'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final width in _widths) {
    group('at ${width.toInt()}dp', () {
      testWidgets('a bottom sheet hides the FAB and closing it restores the FAB', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        expect(fabVisible(), isTrue, reason: 'FAB starts visible with no modal open');

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        expect(fabVisible(), isFalse, reason: 'sheet is up, FAB must be out of the way');

        // Dismiss via the barrier, the way a user taps away from a sheet.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(fabVisible(), isTrue, reason: 'FAB must come back once the sheet closes');
      });

      testWidgets('FAB stays hidden until every stacked modal closes', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('open dialog'));
        await tester.pumpAndSettle();
        expect(fabVisible(), isFalse);

        // Only the dialog closes; the sheet is still up.
        Navigator.of(tester.element(find.text('dialog'))).pop();
        await tester.pumpAndSettle();
        expect(fabVisible(), isFalse, reason: 'sheet still open, FAB must stay hidden');

        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(fabVisible(), isTrue, reason: 'last modal closed, FAB restored');
      });

      testWidgets('a plain page route leaves the FAB alone', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());

        await tester.tap(find.text('open page'));
        await tester.pumpAndSettle();
        expect(fabVisible(), isTrue, reason: 'only modals hide the FAB, not ordinary navigation');
      });
    });
  }
}
