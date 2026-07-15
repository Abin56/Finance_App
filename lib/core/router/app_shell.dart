import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/dialogs/add_entry_menu.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../extensions/context_extensions.dart';
import 'fab_visibility.dart';

/// Bottom-navigation shell wrapping the five screen tabs (Dashboard,
/// History, Cash Flow, People, More) plus a "+" button that opens the
/// add-entry sheet rather than navigating to a sixth branch.
/// Built on go_router's [StatefulNavigationShell] so each tab keeps its
/// own navigation stack and scroll position when switching between them.
///
/// Uses Flutter's Material 3 [NavigationBar], which lays out and spaces
/// its destinations itself — that avoids the alignment drift a hand-rolled
/// Row + fixed-width notch gap produced across different screen widths.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  /// Material's "quick" band — long enough to read as a deliberate motion,
  /// short enough not to delay a tap on the sheet underneath.
  static const _fabToggleDuration = Duration(milliseconds: 250);

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Dashboard'),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet_rounded),
      label: 'Cash Flow',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outline_rounded),
      selectedIcon: Icon(Icons.people_rounded),
      label: 'People',
    ),
    NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded), label: 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fabVisible = ref.watch(fabVisibleProvider);

    return Scaffold(
      body: navigationShell,
      // Scaled/faded in place rather than swapped for null: the FAB keeps its
      // slot, so nothing else in the Scaffold reflows as it comes and goes.
      // IgnorePointer stops the invisible FAB from swallowing taps meant for
      // the sheet beneath it — the actual bug being fixed.
      floatingActionButton: IgnorePointer(
        ignoring: !fabVisible,
        child: AnimatedScale(
          scale: fabVisible ? 1 : 0,
          duration: _fabToggleDuration,
          curve: fabVisible ? Curves.easeOutBack : Curves.easeInCubic,
          child: AnimatedOpacity(
            opacity: fabVisible ? 1 : 0,
            duration: _fabToggleDuration,
            curve: Curves.easeInOut,
            child: _GradientFab(
              heroTag: 'app_shell_fab',
              onPressed: () => showAddEntryMenu(context),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarTheme.of(context).copyWith(
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => context.textTheme.labelLarge?.copyWith(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) =>
              navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
          destinations: _destinations,
        ),
      ),
    );
  }
}

/// Modern gradient FAB — soft shadow, slightly larger than the stock
/// Material FAB, styled to read as an iOS-style "add" button. Wraps the
/// same [onPressed]/[heroTag] the plain [FloatingActionButton] used, so
/// the add-entry sheet logic is unchanged.
class _GradientFab extends StatelessWidget {
  const _GradientFab({required this.heroTag, required this.onPressed});

  final Object heroTag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryGradient,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: AppSizes.iconLg),
          ),
        ),
      ),
    );
  }
}
