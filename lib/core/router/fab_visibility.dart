import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the modal routes (bottom sheets, dialogs, popup menus) currently
/// open inside the shell's branch navigators, so [AppShell] can pull the
/// global FAB out of the way while one is up.
///
/// A sheet opened from a tab screen is pushed onto that branch's Navigator,
/// which lives *inside* the shell `Scaffold`'s body — so it paints below the
/// FAB's slot and the FAB floats over its content. Only branch navigators
/// need this: a route on the root navigator (a pushed screen, or a sheet
/// opened with `useRootNavigator: true`) already covers the whole shell.
///
/// A count rather than a bool keeps nesting correct — a sheet that opens a
/// dialog on top must leave the FAB hidden when only the dialog closes.
class ModalRouteCounter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;

  /// Floors at zero so an unbalanced pop can never drive the count negative
  /// and strand the FAB hidden.
  void decrement() => state = state > 0 ? state - 1 : 0;
}

final modalRouteCountProvider = NotifierProvider<ModalRouteCounter, int>(ModalRouteCounter.new);

/// Whether the global FAB should currently be shown.
final fabVisibleProvider = Provider<bool>((ref) => ref.watch(modalRouteCountProvider) == 0);

/// Attach one instance per [StatefulShellBranch] so every sheet or dialog a
/// tab screen opens hides the FAB automatically — no call-site opt-in, so
/// screens added later inherit the behaviour for free.
///
/// [PopupRoute] is the shared supertype of `ModalBottomSheetRoute`,
/// `DialogRoute` and `PopupMenuRoute`; matching on it rather than on each
/// concrete type is what makes this cover future sheets.
class FabHidingModalObserver extends NavigatorObserver {
  FabHidingModalObserver(this._counter);

  final ModalRouteCounter _counter;

  bool _isModal(Route<dynamic>? route) => route is PopupRoute;

  /// Navigator observers can fire mid-build (a route pushed from `initState`,
  /// or route restoration), and Riverpod forbids writing to a provider while
  /// the tree is building. A microtask lands after the current build but
  /// before the next frame, so the FAB still animates without a visible lag.
  void _defer(void Function() change) => scheduleMicrotask(change);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) _defer(_counter.increment);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) _defer(_counter.decrement);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) _defer(_counter.decrement);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isModal(oldRoute)) _defer(_counter.decrement);
    if (_isModal(newRoute)) _defer(_counter.increment);
  }
}
