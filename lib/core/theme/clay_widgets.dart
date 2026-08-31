import 'package:flutter/material.dart';

import 'clay_theme.dart';

/// Wraps [child] with a subtle press-down scale, the micro-interaction that
/// makes claymorphism surfaces feel "touchable" rather than flat/static.
/// Purely visual — driven by [InkWell.onHighlightChanged] so it rides the
/// same gesture arena as the ink ripple instead of adding a second
/// competing gesture detector.
class ClayPressable extends StatefulWidget {
  const ClayPressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<ClayPressable> createState() => _ClayPressableState();
}

class _ClayPressableState extends State<ClayPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A gradient-filled progress bar — the claymorphism replacement for the
/// stock [LinearProgressIndicator], which only accepts a flat fill color.
/// Renders the same 0–1 [value] semantics, just with a two-stop gradient
/// and a softly rounded pill track.
class ClayProgressBar extends StatelessWidget {
  const ClayProgressBar({
    super.key,
    required this.value,
    required this.colors,
    this.height = 8,
    this.trackColor,
  });

  final double value;
  final List<Color> colors;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppClay.radiusPill),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(
                height: height,
                width: double.infinity,
                color: trackColor ?? colors.last.withValues(alpha: 0.15),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                height: height,
                width: constraints.maxWidth * clamped,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(AppClay.radiusPill),
                  boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The app's general-purpose floating card shell — extracted from the
/// Dashboard's original card widgets so every screen shares one
/// implementation instead of re-deriving it. Shadow lives on an outer,
/// unclipped [Container]; the rounded-corner clip and gradient/tap ripple
/// live on the inner [Material]/[Ink] layer — putting the shadow on the
/// clipped layer crops the blur off entirely, which is why cards restyled
/// without this shell tend to look flat.
class ClayCard extends StatefulWidget {
  const ClayCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.gradient,
    this.isHero = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Overrides the default gradient fill — used for cards that need a flat
  /// semantic tint (e.g. a danger-tinted delete-confirm row) instead of the
  /// standard lit-surface gradient.
  final Color? backgroundColor;

  /// Overrides the fill with a custom gradient (e.g. [AppClay.primaryGradient])
  /// for a screen's hero card — takes precedence over [backgroundColor].
  final Gradient? gradient;

  /// Uses the stronger [AppClay.elevated] shadow instead of [AppClay.soft]
  /// — reserve for a screen's single most prominent card.
  final bool isHero;

  @override
  State<ClayCard> createState() => _ClayCardState();
}

class _ClayCardState extends State<ClayCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed && widget.onTap != null ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          boxShadow: widget.isHero ? AppClay.elevated(context) : AppClay.soft(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Ink(
              decoration: BoxDecoration(
                color: widget.gradient == null ? widget.backgroundColor : null,
                gradient: widget.gradient ?? (widget.backgroundColor == null ? AppClay.cardGradient(context) : null),
              ),
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft, floating circular icon button — the claymorphism replacement for
/// Material's `IconButton.filledTonal`, used for header/app-bar actions
/// (search, edit, back, trash) across every redesigned screen.
class ClayIconButton extends StatelessWidget {
  const ClayIconButton({super.key, required this.icon, this.tooltip, required this.onPressed, this.color});

  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppClay.card(context),
        shape: BoxShape.circle,
        boxShadow: AppClay.soft(context),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: color ?? AppClay.primary),
        tooltip: tooltip,
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
    );
  }
}

/// A gradient-filled floating action button — the claymorphism replacement
/// for the stock Material [FloatingActionButton], used for each redesigned
/// screen's own local "add" action (screens outside the shared app shell
/// own their own FAB rather than inheriting the shell's).
class ClayFab extends StatelessWidget {
  const ClayFab({super.key, required this.icon, required this.onPressed, this.heroTag});

  final IconData icon;
  final VoidCallback onPressed;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppClay.elevated(context),
      ),
      child: FloatingActionButton(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: AppClay.primary,
        elevation: 0,
        highlightElevation: 0,
        child: Ink(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: AppClay.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// A tinted circular icon chip with a soft two-stop gradient fill instead
/// of a flat alpha-tinted color — the small "lit orb" accent used for every
/// list-row leading icon across the app's claymorphism screens.
class ClayIconChip extends StatelessWidget {
  const ClayIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 26,
    this.iconSize = 14,
    this.glow = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  /// Adds a soft colored glow behind the chip — reserve for the most
  /// important accents rather than every row, so it stays a highlight.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppClay.iconChipGradient(color),
        shape: BoxShape.circle,
        boxShadow: glow ? AppClay.glow(color) : null,
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
