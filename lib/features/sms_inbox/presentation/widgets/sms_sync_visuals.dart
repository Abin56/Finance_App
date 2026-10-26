import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_theme.dart';

/// Shared look for SMS Sync's setup surfaces (the SMS Auto Sync card and the
/// unpaired inbox's pairing guide). Presentation only — no state lives here.

/// Zero under the system "remove animations" setting.
Duration smsSyncMotion(BuildContext context, int ms) =>
    MediaQuery.of(context).disableAnimations
    ? Duration.zero
    : Duration(milliseconds: ms);

bool smsSyncReduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

/// Lime only works as a fill on light surfaces; text and thin strokes there
/// use a dark olive-lime instead (matches the web's `--primary-accent-text`).
Color smsSyncAccentInk(BuildContext context) =>
    context.isDarkMode ? context.colors.primary : const Color(0xFF3F6300);

/// A soft lime wash for icon tiles and halos — never a whole-card fill.
Color smsSyncAccentWash(BuildContext context) =>
    context.colors.primary.withValues(alpha: context.isDarkMode ? 0.14 : 0.30);

Color smsSyncMuted(BuildContext context) =>
    context.colors.onSurface.withValues(alpha: 0.62);

enum SmsSyncStepState { done, current, todo, warn, optional }

String smsSyncStepStateLabel(SmsSyncStepState state) => switch (state) {
  SmsSyncStepState.done => 'done',
  SmsSyncStepState.current => 'next',
  SmsSyncStepState.todo => 'not started',
  SmsSyncStepState.warn => 'needs attention',
  SmsSyncStepState.optional => 'optional',
};

/// The tracker's stop marker. Done pops in a check; the current step gets a
/// soft halo that settles once (no endless pulse).
class SmsSyncStepNode extends StatelessWidget {
  const SmsSyncStepNode({super.key, required this.state, required this.index});

  final SmsSyncStepState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = smsSyncAccentInk(context);
    final muted = smsSyncMuted(context);
    final (Color fill, Color border, Color fg) = switch (state) {
      SmsSyncStepState.done => (
        colors.primary,
        colors.primary,
        colors.onPrimary,
      ),
      SmsSyncStepState.current => (colors.surface, ink, ink),
      SmsSyncStepState.warn => (
        colors.error.withValues(alpha: 0.12),
        colors.error,
        colors.error,
      ),
      _ => (colors.surface, smsSyncBorder(context), muted),
    };
    final halo = state == SmsSyncStepState.current
        ? smsSyncAccentWash(context)
        : state == SmsSyncStepState.warn
        ? colors.error.withValues(alpha: 0.14)
        : Colors.transparent;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Keyed by state so the halo grows in once each time the state changes.
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(state),
            tween: Tween(begin: 0, end: 1),
            duration: smsSyncMotion(context, 420),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => OverflowBox(
              maxWidth: 34,
              maxHeight: 34,
              child: Container(
                width: 26 + 8 * t,
                height: 26 + 8 * t,
                decoration: BoxDecoration(color: halo, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: smsSyncMotion(context, 300),
          curve: Curves.easeOutCubic,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
          ),
          alignment: Alignment.center,
          child: _glyph(context, fg),
        ),
      ],
    );
  }

  Widget _glyph(BuildContext context, Color fg) {
    return AnimatedSwitcher(
      duration: smsSyncMotion(context, 320),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: switch (state) {
        SmsSyncStepState.done => Icon(
          Icons.check_rounded,
          key: const ValueKey('done'),
          size: 16,
          color: fg,
        ),
        SmsSyncStepState.warn => Icon(
          Icons.priority_high_rounded,
          key: const ValueKey('warn'),
          size: 14,
          color: fg,
        ),
        _ => Text(
          '$index',
          key: ValueKey('n$index'),
          style: context.textTheme.labelMedium?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      },
    );
  }
}

/// The line between two stops; fills top-down when the step above is done.
class SmsSyncConnector extends StatelessWidget {
  const SmsSyncConnector({super.key, required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final track = smsSyncBorder(context);
    final fill = context.isDarkMode
        ? context.colors.primary
        : smsSyncAccentInk(context);
    return Center(
      child: SizedBox(
        width: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(1),
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: filled ? 1 : 0),
            duration: smsSyncMotion(context, 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: value,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gentle breathing dot for "a sync is running right now". Shown only while
/// the phone reports a running sync; static under reduced motion.
class SmsSyncActivityDot extends StatefulWidget {
  const SmsSyncActivityDot({super.key, required this.color});

  final Color color;

  @override
  State<SmsSyncActivityDot> createState() => _SmsSyncActivityDotState();
}

class _SmsSyncActivityDotState extends State<SmsSyncActivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (smsSyncReduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
                  spreadRadius: 1 + 4 * _c.value,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme V2 tokens, falling back to the ColorScheme where the FlowFi theme
/// extension isn't installed (plain `MaterialApp`s, e.g. widget tests).
Color smsSyncBorder(BuildContext context) =>
    Theme.of(context).extension<FlowFiColors>()?.border ??
    context.colors.outline;

Color smsSyncMutedSurface(BuildContext context) =>
    Theme.of(context).extension<FlowFiColors>()?.mutedSurface ??
    context.colors.surfaceContainerHighest;
