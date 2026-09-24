import 'package:flutter/material.dart';

/// A small tinted circular icon surface — the leading icon/avatar slot used
/// by list rows (transactions, people, accounts, bills, loans) and quick
/// actions. Replaces `ClayIconChip`'s gradient-filled "lit orb": a flat,
/// low-alpha tint reads as calmer and more consistent with Theme V2's
/// "background separation, not decoration" card language.
class FlowFiIconChip extends StatelessWidget {
  const FlowFiIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize,
  }) : _emphasized = false,
       emphasisForeground = null;

  /// A solid-fill variant for an *active/selected* state (e.g. a selected
  /// quick action) — per the color-usage rule, this is one of the few
  /// places a solid lime fill belongs outside buttons/CTAs.
  const FlowFiIconChip.emphasized({
    super.key,
    required this.icon,
    required this.color,
    required this.emphasisForeground,
    this.size = 40,
    this.iconSize,
  }) : _emphasized = true;

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;
  final bool _emphasized;

  /// [FlowFiIconChip.emphasized] only — the icon color drawn on top of the
  /// solid [color] fill (e.g. near-black on a lime chip).
  final Color? emphasisForeground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _emphasized ? color : color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: iconSize ?? size * 0.46,
        color: _emphasized ? emphasisForeground : color,
      ),
    );
  }
}
